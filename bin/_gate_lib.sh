# Shared plumbing for the bin/ gate scripts.
#
# Every check reports its name, its result, its duration and — when it fails —
# the reason, in a form a human can read and the Stop Gate (M00-14) can parse.
# A gate that only prints a stack trace forces the next reader to rediscover what
# failed; the loop cannot act on that at all (Annex I §12, Annex H §4).
#
# Sourced, never executed.

GATE_NAME=""
GATE_FORMAT="text"
GATE_FAILURES=0
GATE_STARTED_AT=0
GATE_RESULTS_FILE=""

gate_begin() {
  GATE_NAME="$1"
  GATE_FORMAT="${2:-text}"
  GATE_FAILURES=0
  GATE_STARTED_AT="$(gate_now_ms)"
  GATE_RESULTS_FILE="$(mktemp -t opanel-gate)"

  case "$GATE_FORMAT" in
    text|json) ;;
    *) echo "unknown format: $GATE_FORMAT (expected text or json)" >&2; exit 2 ;;
  esac
}

gate_now_ms() {
  # `date +%s%3N` is GNU-only; this works on macOS too.
  python3 -c 'import time; print(int(time.time() * 1000))'
}

# gate_run <check-name> <command...>
gate_run() {
  local check="$1"; shift
  local started output status duration

  started="$(gate_now_ms)"
  output="$("$@" 2>&1)"
  status=$?
  duration=$(( $(gate_now_ms) - started ))

  if [ "$status" -eq 0 ]; then
    gate_record "$check" "pass" "$duration" ""
    [ "$GATE_FORMAT" = "text" ] && printf '  %-22s PASS  %sms\n' "$check" "$duration"
  else
    GATE_FAILURES=$(( GATE_FAILURES + 1 ))
    gate_record "$check" "fail" "$duration" "$output"
    if [ "$GATE_FORMAT" = "text" ]; then
      printf '  %-22s FAIL  %sms\n' "$check" "$duration"
      printf '%s\n' "$output" | sed 's/^/      /'
    fi
  fi

  return 0
}

gate_skip() {
  local check="$1" reason="$2"
  gate_record "$check" "skip" 0 "$reason"
  [ "$GATE_FORMAT" = "text" ] && printf '  %-22s SKIP  %s\n' "$check" "$reason"
  return 0
}

gate_fail() {
  local check="$1" reason="$2"
  GATE_FAILURES=$(( GATE_FAILURES + 1 ))
  gate_record "$check" "fail" 0 "$reason"
  if [ "$GATE_FORMAT" = "text" ]; then
    printf '  %-22s FAIL  %s\n' "$check" "$reason"
  fi
  return 0
}

gate_pass() {
  local check="$1" detail="${2:-}"
  gate_record "$check" "pass" 0 "$detail"
  [ "$GATE_FORMAT" = "text" ] && printf '  %-22s PASS  %s\n' "$check" "$detail"
  return 0
}

gate_record() {
  python3 - "$GATE_RESULTS_FILE" "$1" "$2" "$3" "$4" <<'PY'
import json, sys

path, name, result, duration, reason = sys.argv[1:6]
try:
    with open(path) as handle:
        entries = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError):
    entries = []

entries.append({
    "check": name,
    "result": result,
    "duration_ms": int(duration),
    # Gate output is archived as evidence. Truncating keeps a runaway compiler
    # dump from burying the reason that matters.
    "reason": reason[:4000],
})

with open(path, "w") as handle:
    json.dump(entries, handle)
PY
}

gate_finish() {
  local duration result
  duration=$(( $(gate_now_ms) - GATE_STARTED_AT ))
  if [ "$GATE_FAILURES" -eq 0 ]; then result="pass"; else result="fail"; fi

  if [ "$GATE_FORMAT" = "json" ]; then
    python3 - "$GATE_RESULTS_FILE" "$GATE_NAME" "$result" "$duration" <<'PY'
import json, sys

path, name, result, duration = sys.argv[1:5]
try:
    with open(path) as handle:
        checks = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError):
    checks = []

print(json.dumps({
    "gate": name,
    "result": result,
    "duration_ms": int(duration),
    "checks": checks,
}, indent=2))
PY
  else
    printf '%s: %s (%sms)\n' "$GATE_NAME" "$(echo "$result" | tr '[:lower:]' '[:upper:]')" "$duration"
  fi

  rm -f "$GATE_RESULTS_FILE"
  [ "$GATE_FAILURES" -eq 0 ] || exit 1
  exit 0
}

# gate_files <all|changed> <regex>
#
# In `changed` scope the set is the working tree diff against the merge base with
# the default branch, plus anything staged. That is what the pre-commit budget is
# measured against.
gate_files() {
  local scope="$1" pattern="$2" base

  if [ "$scope" = "all" ]; then
    git ls-files | grep -E "$pattern" || true
    return 0
  fi

  base="$(git merge-base HEAD "${OPANEL_GATE_BASE:-main}" 2>/dev/null || git rev-parse HEAD)"
  {
    git diff --name-only --diff-filter=ACMR "$base"
    git diff --name-only --diff-filter=ACMR --cached
  } | sort -u | grep -E "$pattern" | while read -r file; do
    [ -e "$file" ] && printf '%s\n' "$file"
  done || true
}
