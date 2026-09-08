#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${OPANEL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
MILESTONE="${1:-}"

case "$MILESTONE" in
  M[0-9][0-9]) ;;
  *) printf 'invalid milestone: %s\n' "$MILESTONE" >&2; exit 20 ;;
esac

MILESTONE_DIR="$ROOT/docs/implementation/$MILESTONE"
STATE="$MILESTONE_DIR/review-state.json"
FIX_GOAL="$ROOT/docs/goals/FIX_REVIEW_FINDINGS.md"

for required in "$STATE" "$FIX_GOAL"; do
  [ -f "$required" ] || { printf 'missing required file: %s\n' "$required" >&2; exit 20; }
done
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 20; }
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { printf 'Claude CLI is required\n' >&2; exit 20; }

[ "$(jq -r '.status' "$STATE")" = "fixing" ] || {
  printf 'review-state must be fixing\n' >&2
  exit 20
}

FIX_ATTEMPT="$(jq -r '.fixAttempt' "$STATE")"
REVIEW_ATTEMPT="$(jq -r '.reviewAttempt' "$STATE")"
FIX_PADDED="$(printf '%02d' "$FIX_ATTEMPT")"
REVIEW_PADDED="$(printf '%02d' "$REVIEW_ATTEMPT")"
REVIEW_FILE="$MILESTONE_DIR/CODEX_REVIEW_${REVIEW_PADDED}.md"
FIX_REPORT="$MILESTONE_DIR/FIX_REPORT_${FIX_PADDED}.md"

[ -f "$REVIEW_FILE" ] || { printf 'missing review artifact: %s\n' "$REVIEW_FILE" >&2; exit 20; }
[ ! -e "$FIX_REPORT" ] || { printf 'fix artifact already exists: %s\n' "$FIX_REPORT" >&2; exit 20; }

TEMP_LOG="$(mktemp "${TMPDIR:-/tmp}/opanel-claude-fix.XXXXXX")"
trap 'rm -f "$TEMP_LOG"' EXIT INT TERM

CONTROL_FILES=(
  "$ROOT/.claude/settings.json"
  "$ROOT/docs/goals/REVIEW_MILESTONE.md"
  "$ROOT/docs/goals/FIX_REVIEW_FINDINGS.md"
  "$SCRIPT_DIR/agent-orchestrator.sh"
  "$SCRIPT_DIR/run-codex-review.sh"
  "$SCRIPT_DIR/run-claude-fix.sh"
  "$SCRIPT_DIR/schemas/codex-review.schema.json"
  "$SCRIPT_DIR/schemas/review-state.schema.json"
  "$REVIEW_FILE"
)

for previous_review in "$MILESTONE_DIR"/CODEX_REVIEW_*.md; do
  [ -f "$previous_review" ] || continue
  CONTROL_FILES+=("$previous_review")
done

control_manifest() {
  local file
  for file in "${CONTROL_FILES[@]}"; do
    [ -f "$file" ] || return 1
    cksum "$file"
  done
}

CONTROL_BEFORE="$(control_manifest)" || {
  printf 'orchestrator control files are incomplete\n' >&2
  exit 20
}
STATE_GUARD_BEFORE="$(jq -c '{milestone, reviewAttempt, fixAttempt,
  maxReviewAttempts, maxFixAttempts, lastReviewer, acceptedAt}' "$STATE")"

PROMPT=$(cat <<EOF
Você está na fase FIX do Milestone $MILESTONE como IMPLEMENTER.

Siga integralmente $FIX_GOAL.
O review bloqueante é $REVIEW_FILE.
Esta é a tentativa de correção $FIX_ATTEMPT.

Corrija somente findings Critical e High, execute testes e gates e gere
$FIX_REPORT. Quando tudo estiver pronto para nova verificação, altere
$STATE para status ready_for_review, com verdict e counts nulos.

Não declare ACCEPTED ou human_acceptance. Somente o Codex reviewer pode emitir
o verdict. Não inicie outro Milestone.
EOF
)

set +e
OPANEL_MILESTONE="$MILESTONE" \
OPANEL_FIX_ATTEMPT="$FIX_ATTEMPT" \
OPANEL_REVIEW_STATE="$STATE" \
"$CLAUDE_BIN" --print \
  --permission-mode "${CLAUDE_PERMISSION_MODE:-acceptEdits}" \
  --allowedTools "Read,Edit,Write,Bash,Glob,Grep" \
  --permission-prompts none \
  --no-session-persistence \
  --output-format text \
  "$PROMPT" >"$TEMP_LOG" 2>&1
CLAUDE_STATUS=$?
set -e

if [ "$CLAUDE_STATUS" -ne 0 ]; then
  printf 'Claude fix failed with exit code %s\n' "$CLAUDE_STATUS" >&2
  tail -n 40 "$TEMP_LOG" >&2 || true
  exit 20
fi

CONTROL_AFTER="$(control_manifest)" || {
  printf 'Claude removed an orchestrator control file\n' >&2
  exit 20
}
[ "$CONTROL_BEFORE" = "$CONTROL_AFTER" ] || {
  printf 'Claude modified orchestrator control files during a fix\n' >&2
  exit 20
}
STATE_GUARD_AFTER="$(jq -c '{milestone, reviewAttempt, fixAttempt,
  maxReviewAttempts, maxFixAttempts, lastReviewer, acceptedAt}' "$STATE")"
[ "$STATE_GUARD_BEFORE" = "$STATE_GUARD_AFTER" ] || {
  printf 'Claude modified protected review-state fields during a fix\n' >&2
  exit 20
}

[ -s "$FIX_REPORT" ] || { printf 'Claude did not create %s\n' "$FIX_REPORT" >&2; exit 20; }
[ "$(jq -r '.status' "$STATE")" = "ready_for_review" ] || {
  printf 'Claude did not transition review-state to ready_for_review\n' >&2
  exit 20
}
[ "$(jq -r '.verdict' "$STATE")" = "null" ] || {
  printf 'Claude must clear the previous verdict before review\n' >&2
  exit 20
}
