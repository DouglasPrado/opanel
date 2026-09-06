#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATOR="$REPO_ROOT/scripts/agent-orchestrator.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/opanel-orchestrator-test.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
PASSED=0

trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM
mkdir -p "$FAKE_BIN"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [ "$expected" = "$actual" ] || fail "$message (expected=$expected actual=$actual)"
}

assert_file() {
  [ -s "$1" ] || fail "expected non-empty file: $1"
}

pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS: %s\n' "$1"
}

cat > "$FAKE_BIN/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail

OUTPUT=""
HAS_READ_ONLY=0
HAS_NEVER=0
HAS_SCHEMA=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      [ "${2:-}" = "read-only" ] && HAS_READ_ONLY=1
      shift 2
      ;;
    -c)
      [ "${2:-}" = 'approval_policy="never"' ] && HAS_NEVER=1
      shift 2
      ;;
    --output-schema)
      [ -f "${2:-}" ] && HAS_SCHEMA=1
      shift 2
      ;;
    --output-last-message)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --cd|--color)
      shift 2
      ;;
    *) shift ;;
  esac
done

[ "$HAS_READ_ONLY" -eq 1 ] || exit 71
[ "$HAS_NEVER" -eq 1 ] || exit 72
[ "$HAS_SCHEMA" -eq 1 ] || exit 73
[ -n "$OUTPUT" ] || exit 74

COUNT_FILE="$OPANEL_ROOT/fake-codex-count"
COUNT=0
[ ! -f "$COUNT_FILE" ] || read -r COUNT < "$COUNT_FILE"
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$COUNT_FILE"

case "${FAKE_CODEX_MODE:-accepted}" in
  accepted)
    cat > "$OUTPUT" <<'JSON'
{"verdict":"ACCEPTED","criticalCount":0,"highCount":0,"mediumCount":0,"lowCount":0,"findings":[],"reportMarkdown":"All required evidence passed."}
JSON
    ;;
  reject_then_accept)
    if [ "$COUNT" -eq 1 ]; then
      cat > "$OUTPUT" <<'JSON'
{"verdict":"NOT_ACCEPTED","criticalCount":0,"highCount":1,"mediumCount":0,"lowCount":0,"findings":[{"id":"HIGH-001","severity":"High","story":"M00-01","file":"example.rb","problem":"Missing behavior","impact":"Acceptance criterion fails","evidence":"Test is absent","recommendation":"Add implementation and test"}],"reportMarkdown":"One blocking finding."}
JSON
    else
      cat > "$OUTPUT" <<'JSON'
{"verdict":"ACCEPTED","criticalCount":0,"highCount":0,"mediumCount":0,"lowCount":0,"findings":[],"reportMarkdown":"The blocking finding was independently verified."}
JSON
    fi
    ;;
  always_reject)
    cat > "$OUTPUT" <<'JSON'
{"verdict":"NOT_ACCEPTED","criticalCount":0,"highCount":1,"mediumCount":0,"lowCount":0,"findings":[{"id":"HIGH-003","severity":"High","story":"M00-01","file":"example.rb","problem":"Still broken","impact":"Milestone cannot be accepted","evidence":"Reproduction remains red","recommendation":"Human decision required after cap"}],"reportMarkdown":"The blocking finding remains."}
JSON
    ;;
  inconsistent)
    cat > "$OUTPUT" <<'JSON'
{"verdict":"ACCEPTED","criticalCount":0,"highCount":1,"mediumCount":0,"lowCount":0,"findings":[],"reportMarkdown":"Invalid result."}
JSON
    ;;
esac
FAKE_CODEX

cat > "$FAKE_BIN/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail

HAS_MODE=0
HAS_NO_PROMPTS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --permission-mode)
      [ "${2:-}" = "acceptEdits" ] && HAS_MODE=1
      shift 2
      ;;
    --permission-prompts)
      [ "${2:-}" = "none" ] && HAS_NO_PROMPTS=1
      shift 2
      ;;
    --output-format)
      shift 2
      ;;
    *) shift ;;
  esac
done

[ "$HAS_MODE" -eq 1 ] || exit 81
[ "$HAS_NO_PROMPTS" -eq 1 ] || exit 82

PADDED="$(printf '%02d' "$OPANEL_FIX_ATTEMPT")"
REPORT="$OPANEL_ROOT/docs/implementation/$OPANEL_MILESTONE/FIX_REPORT_${PADDED}.md"
printf '# Fix Report %s\n\nBlocking findings fixed and gates green.\n' "$PADDED" > "$REPORT"

if [ "${FAKE_CLAUDE_TAMPER:-0}" = "1" ]; then
  printf '{"tampered":true}\n' > "$OPANEL_ROOT/.claude/settings.json"
fi

TEMPORARY="$(mktemp "${OPANEL_REVIEW_STATE}.tmp.XXXXXX")"
jq '
  .status = "ready_for_review" |
  .verdict = null |
  .criticalCount = null |
  .highCount = null |
  .mediumCount = null |
  .lowCount = null
' "$OPANEL_REVIEW_STATE" > "$TEMPORARY"
mv "$TEMPORARY" "$OPANEL_REVIEW_STATE"
FAKE_CLAUDE

chmod +x "$FAKE_BIN/codex" "$FAKE_BIN/claude"

make_fixture() {
  local name="$1"
  local status="$2"
  local max_reviews="${3:-3}"
  local root="$TEST_ROOT/$name"
  local milestone_dir="$root/docs/implementation/M00"

  mkdir -p "$milestone_dir" "$root/docs/goals" "$root/runtime" "$root/.claude"
  printf '{}\n' > "$root/.claude/settings.json"
  printf '# Review goal\n' > "$root/docs/goals/REVIEW_MILESTONE.md"
  printf '# Fix goal\n' > "$root/docs/goals/FIX_REVIEW_FINDINGS.md"
  printf 'Status: READY_FOR_REVIEW\n' > "$milestone_dir/MILESTONE_REPORT.md"
  printf '%s\n' '{"stories":[{"id":"M00-01","required":true,"status":"done"}]}' \
    > "$milestone_dir/tasks.json"
  jq -n \
    --arg status "$status" \
    --argjson maxReviews "$max_reviews" \
    '{milestone:"M00",status:$status,reviewAttempt:0,fixAttempt:0,
      maxReviewAttempts:$maxReviews,maxFixAttempts:3,lastReviewer:null,
      verdict:null,criticalCount:null,highCount:null,mediumCount:null,
      lowCount:null,lastError:null,blockedReason:null,acceptedAt:null,
      updatedAt:null}' > "$milestone_dir/review-state.json"
  printf '%s\n' "$root"
}

run_orchestrator() {
  local root="$1"
  local mode="$2"
  local tamper="${3:-0}"

  OPANEL_ROOT="$root" \
  OPANEL_ORCHESTRATOR_RUNTIME_DIR="$root/runtime" \
  CODEX_BIN="$FAKE_BIN/codex" \
  CLAUDE_BIN="$FAKE_BIN/claude" \
  FAKE_CODEX_MODE="$mode" \
  FAKE_CLAUDE_TAMPER="$tamper" \
    "$ORCHESTRATOR" run M00
}

ROOT="$(make_fixture noop implementing)"
run_orchestrator "$ROOT" accepted
assert_eq implementing "$(jq -r '.status' "$ROOT/docs/implementation/M00/review-state.json")" \
  "implementing must be a no-op"
[ ! -e "$ROOT/fake-codex-count" ] || fail "Codex ran while implementation was active"
pass "implementing is inert"

ROOT="$(make_fixture accepted ready_for_review)"
run_orchestrator "$ROOT" accepted
STATE="$ROOT/docs/implementation/M00/review-state.json"
assert_eq human_acceptance "$(jq -r '.status' "$STATE")" "accepted review must reach human gate"
assert_eq ACCEPTED "$(jq -r '.verdict' "$STATE")" "accepted verdict must persist"
assert_eq 1 "$(jq -r '.reviewAttempt' "$STATE")" "review attempt must increment"
assert_eq 0 "$(jq -r '.fixAttempt' "$STATE")" "Claude must not run after acceptance"
assert_file "$ROOT/docs/implementation/M00/CODEX_REVIEW_01.md"
pass "ready_for_review reaches human_acceptance after ACCEPTED"

ROOT="$(make_fixture correction ready_for_review)"
run_orchestrator "$ROOT" reject_then_accept
STATE="$ROOT/docs/implementation/M00/review-state.json"
assert_eq human_acceptance "$(jq -r '.status' "$STATE")" "fixed milestone must reach human gate"
assert_eq 2 "$(jq -r '.reviewAttempt' "$STATE")" "second independent review must run"
assert_eq 1 "$(jq -r '.fixAttempt' "$STATE")" "one Claude fix must run"
assert_file "$ROOT/docs/implementation/M00/CODEX_REVIEW_01.md"
assert_file "$ROOT/docs/implementation/M00/FIX_REPORT_01.md"
assert_file "$ROOT/docs/implementation/M00/CODEX_REVIEW_02.md"
pass "NOT_ACCEPTED returns to Claude and is independently re-reviewed"

ROOT="$(make_fixture capped ready_for_review 3)"
if run_orchestrator "$ROOT" always_reject; then
  fail "non-converging reviews should return a failure"
fi
STATE="$ROOT/docs/implementation/M00/review-state.json"
assert_eq blocked "$(jq -r '.status' "$STATE")" "attempt cap must block"
assert_eq MAX_REVIEW_ATTEMPTS_REACHED "$(jq -r '.blockedReason' "$STATE")" \
  "attempt cap must provide an objective reason"
assert_eq 3 "$(jq -r '.reviewAttempt' "$STATE")" "review cap must be exact"
assert_eq 2 "$(jq -r '.fixAttempt' "$STATE")" "third rejection must not start another fix"
pass "three rejected reviews block without an infinite loop"

ROOT="$(make_fixture invalid ready_for_review)"
if run_orchestrator "$ROOT" inconsistent; then
  fail "inconsistent Codex output should return a failure"
fi
STATE="$ROOT/docs/implementation/M00/review-state.json"
assert_eq blocked "$(jq -r '.status' "$STATE")" "invalid reviewer output must block"
assert_eq CODEX_REVIEW_EXECUTION_FAILED "$(jq -r '.blockedReason' "$STATE")" \
  "invalid reviewer output must have a deterministic reason"
pass "inconsistent reviewer output fails closed"

ROOT="$(make_fixture fix_cap fix_required)"
STATE="$ROOT/docs/implementation/M00/review-state.json"
TEMPORARY="$(mktemp "${STATE}.tmp.XXXXXX")"
jq '.fixAttempt = .maxFixAttempts' "$STATE" > "$TEMPORARY"
mv "$TEMPORARY" "$STATE"
if run_orchestrator "$ROOT" accepted; then
  fail "exhausted fix attempts should return a failure"
fi
assert_eq blocked "$(jq -r '.status' "$STATE")" "fix cap must block"
assert_eq MAX_FIX_ATTEMPTS_REACHED "$(jq -r '.blockedReason' "$STATE")" \
  "fix cap must provide an objective reason"
pass "fix attempts are capped"

ROOT="$(make_fixture tamper ready_for_review)"
if run_orchestrator "$ROOT" reject_then_accept 1; then
  fail "Claude control-file mutation should return a failure"
fi
STATE="$ROOT/docs/implementation/M00/review-state.json"
assert_eq blocked "$(jq -r '.status' "$STATE")" "control-file mutation must block"
assert_eq CLAUDE_FIX_EXECUTION_FAILED "$(jq -r '.blockedReason' "$STATE")" \
  "control-file mutation must fail closed"
pass "Claude cannot silently modify orchestrator controls during fix"

printf 'All %s orchestrator tests passed.\n' "$PASSED"
