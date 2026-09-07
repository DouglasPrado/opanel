#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${OPANEL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CODEX_BIN="${CODEX_BIN:-codex}"
SCHEMA="$SCRIPT_DIR/schemas/codex-review.schema.json"
MILESTONE="${1:-}"

case "$MILESTONE" in
  M[0-9][0-9]) ;;
  *) printf 'invalid milestone: %s\n' "$MILESTONE" >&2; exit 20 ;;
esac

MILESTONE_DIR="$ROOT/docs/implementation/$MILESTONE"
STATE="$MILESTONE_DIR/review-state.json"
TASKS="$MILESTONE_DIR/tasks.json"
REPORT="$MILESTONE_DIR/MILESTONE_REPORT.md"
REVIEW_GOAL="$ROOT/docs/goals/REVIEW_MILESTONE.md"

for required in "$STATE" "$TASKS" "$REPORT" "$REVIEW_GOAL" "$SCHEMA"; do
  [ -f "$required" ] || { printf 'missing required file: %s\n' "$required" >&2; exit 20; }
done
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 20; }
command -v "$CODEX_BIN" >/dev/null 2>&1 || { printf 'Codex CLI is required\n' >&2; exit 20; }

[ "$(jq -r '.status' "$STATE")" = "reviewing" ] || {
  printf 'review-state must be reviewing\n' >&2
  exit 20
}

NOT_DONE="$(jq '[.stories[] | select(.required == true and .status != "done")] | length' "$TASKS")"
BLOCKED="$(jq '[.stories[] | select(.required == true and .status == "blocked")] | length' "$TASKS")"
[ "$NOT_DONE" -eq 0 ] || { printf 'required Stories are not done\n' >&2; exit 20; }
[ "$BLOCKED" -eq 0 ] || { printf 'required Stories are blocked\n' >&2; exit 20; }
grep -q '^Status: READY_FOR_REVIEW$' "$REPORT" || {
  printf 'MILESTONE_REPORT.md is not READY_FOR_REVIEW\n' >&2
  exit 20
}

ATTEMPT="$(jq -r '.reviewAttempt' "$STATE")"
ATTEMPT_PADDED="$(printf '%02d' "$ATTEMPT")"
REVIEW_FILE="$MILESTONE_DIR/CODEX_REVIEW_${ATTEMPT_PADDED}.md"
[ ! -e "$REVIEW_FILE" ] || { printf 'review artifact already exists: %s\n' "$REVIEW_FILE" >&2; exit 20; }

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opanel-codex-review.XXXXXX")"
RESULT_FILE="$TEMP_DIR/result.json"
CLI_LOG="$TEMP_DIR/codex.log"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

# The CLI log lives in TEMP_DIR, which the trap removes on every exit. When the
# runner fails, the 40 lines it echoes to stderr are all that survives, and the
# cause — a usage limit, a network error, a malformed response — is usually
# further up. A block whose diagnosis was thrown away is what Annex H forbids,
# so keep the whole log where the orchestrator's own log points.
FAILURE_LOG_DIR="${TMPDIR:-/tmp}/opanel-agent-orchestrator"
FAILURE_LOG="$FAILURE_LOG_DIR/${MILESTONE}-codex-${ATTEMPT_PADDED}.log"

preserve_cli_log() {
  mkdir -p "$FAILURE_LOG_DIR" || return 0
  cp "$CLI_LOG" "$FAILURE_LOG" 2>/dev/null || return 0
  printf 'full Codex log: %s\n' "$FAILURE_LOG" >&2
}

PROMPT=$(cat <<EOF
Você é exclusivamente o REVIEWER independente do Milestone $MILESTONE do Opanel.

Siga integralmente $REVIEW_GOAL e revise o alvo $MILESTONE_DIR.
Leia AGENTS.md, docs/MASTER.md e docs/AGENT_RULES.md antes da revisão.

Esta é a tentativa de review $ATTEMPT. Leia todos os CODEX_REVIEW_*.md e
FIX_REPORT_*.md anteriores, além do git diff/log e da implementação completa.
Não confie nas afirmações do implementer. Você não pode executar suíte nem
gates em sandbox read-only: verifique-os por leitura de código, specs e git log.

Você está tecnicamente em sandbox read-only. Não altere arquivos, não corrija
código, não faça commits e não modifique tasks.json ou review-state.json.

A resposta final deve obedecer ao JSON Schema fornecido. Em reportMarkdown,
produza o relatório completo exigido por REVIEW_MILESTONE.md. Classifique todo
requisito bloqueante como Critical ou High. ACCEPTED exige Critical=0, High=0,
todas as Stories e critérios obrigatórios comprovados e todos os gates verdes.
NOT_ACCEPTED exige ao menos um finding Critical ou High acionável.
EOF
)

set +e
"$CODEX_BIN" exec \
  --strict-config \
  --ephemeral \
  --sandbox read-only \
  -c 'approval_policy="never"' \
  --cd "$ROOT" \
  --output-schema "$SCHEMA" \
  --output-last-message "$RESULT_FILE" \
  --color never \
  "$PROMPT" >"$CLI_LOG" 2>&1
CODEX_STATUS=$?
set -e

if [ "$CODEX_STATUS" -ne 0 ]; then
  printf 'Codex review failed with exit code %s\n' "$CODEX_STATUS" >&2
  tail -n 40 "$CLI_LOG" >&2 || true
  preserve_cli_log
  exit 20
fi

if ! jq -e '
  (.criticalCount == ([.findings[] | select(.severity == "Critical")] | length)) and
  (.highCount == ([.findings[] | select(.severity == "High")] | length)) and
  (.mediumCount == ([.findings[] | select(.severity == "Medium")] | length)) and
  (.lowCount == ([.findings[] | select(.severity == "Low")] | length)) and
  ((.verdict == "ACCEPTED" and .criticalCount == 0 and .highCount == 0) or
   (.verdict == "NOT_ACCEPTED" and (.criticalCount + .highCount) > 0))
' "$RESULT_FILE" >/dev/null; then
  printf 'Codex returned an inconsistent review result\n' >&2
  cat "$RESULT_FILE" >&2 || true
  preserve_cli_log
  exit 20
fi

VERDICT="$(jq -r '.verdict' "$RESULT_FILE")"
CRITICAL="$(jq -r '.criticalCount' "$RESULT_FILE")"
HIGH="$(jq -r '.highCount' "$RESULT_FILE")"
MEDIUM="$(jq -r '.mediumCount' "$RESULT_FILE")"
LOW="$(jq -r '.lowCount' "$RESULT_FILE")"

{
  printf '# Codex Milestone Review %s — Attempt %s\n\n' "$MILESTONE" "$ATTEMPT_PADDED"
  printf '%s\n\n' 'Reviewer role: Codex (read-only)'
  jq -r '.reportMarkdown' "$RESULT_FILE"
  printf '\n\nVERDICT: %s\n\n' "$VERDICT"
  printf 'Critical: %s\nHigh: %s\nMedium: %s\nLow: %s\n' \
    "$CRITICAL" "$HIGH" "$MEDIUM" "$LOW"
} > "$REVIEW_FILE"

jq -nc \
  --arg verdict "$VERDICT" \
  --argjson criticalCount "$CRITICAL" \
  --argjson highCount "$HIGH" \
  --argjson mediumCount "$MEDIUM" \
  --argjson lowCount "$LOW" \
  '{verdict: $verdict, criticalCount: $criticalCount, highCount: $highCount,
    mediumCount: $mediumCount, lowCount: $lowCount}'

[ "$VERDICT" = "ACCEPTED" ] && exit 0
exit 10
