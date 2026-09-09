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
# How many results the gate believes it produced. Compared against how many were
# actually written: every way a run can be cut short — a temporary file that
# cannot be created, a killed interpreter, a loop that never started — otherwise
# ends with an empty result list, and an empty result list reads as "nothing
# failed".
GATE_EXPECTED_CHECKS=0
# The names, in order. What a gate ran is part of its result: "eight checks
# passed" and "these eight checks passed" are different claims, and only the
# second one can be verified afterwards.
GATE_CHECK_NAMES=""

gate_begin() {
  GATE_NAME="$1"
  GATE_FORMAT="${2:-text}"
  GATE_FAILURES=0
  GATE_EXPECTED_CHECKS=0
  GATE_CHECK_NAMES=""
  GATE_STARTED_AT="$(gate_now_ms)"

  # An explicit template rather than `mktemp -t opanel-gate`. BSD mktemp appends
  # the random suffix to a `-t` argument; GNU coreutils — which is what the
  # Ubuntu runner in .github/workflows has — requires the template to end in at
  # least three X's and exits non-zero without them. So the gate died at
  # gate_begin on every Linux runner, before a single check ran.
  if ! GATE_RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/opanel-gate.XXXXXXXX")"; then
    echo "$GATE_NAME: cannot create a results file — the gate did not run" >&2
    exit 2
  fi

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

  # GATE_ONLY narrows a run to named checks. It exists for the specs that prove
  # one check rejects one planted failure: proving `no-stray-files` used to cost
  # a full pre-commit — the suite, the secret scan, everything — 123 seconds to
  # assert one field.
  #
  # It narrows, it never relaxes: a check that runs still has to pass, and
  # nothing in bin/gate's own gates passes GATE_ONLY. A run that used it says so
  # in its report, so a green result cannot be mistaken for a full one.
  if [ -n "${GATE_ONLY:-}" ] && ! printf '%s' ",$GATE_ONLY," | grep -q ",$check,"; then
    gate_skip "$check" "not selected by --only"
    return 0
  fi

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
  GATE_EXPECTED_CHECKS=$(( GATE_EXPECTED_CHECKS + 1 ))
  GATE_CHECK_NAMES="$GATE_CHECK_NAMES $1"
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

# gate_write_json <path>
#
# The machine-readable result, written to a file without ending the run and
# regardless of the display format. CI needs both: a log a person can read while
# the job is running, and a result the Merge Gate can require by name. Rendering
# one from the other, or running the gate twice to get both, is how they start
# disagreeing.
gate_write_json() {
  local path="$1" duration result commit branch dirty
  duration=$(( $(gate_now_ms) - GATE_STARTED_AT ))
  if [ "$GATE_FAILURES" -eq 0 ]; then result="pass"; else result="fail"; fi

  # Which code this result describes. A job name and `result: pass`, on their
  # own, say that something passed and nothing about what: the archived results
  # of two different branches are indistinguishable. `dirty` matters as much —
  # a green result produced over uncommitted changes was not produced over the
  # commit it sits next to.
  commit="$(git rev-parse HEAD 2>/dev/null || echo "")"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty="true"; else dirty="false"; fi

  mkdir -p "$(dirname "$path")" || return 1
  python3 - "$GATE_RESULTS_FILE" "$GATE_NAME" "$result" "$duration" "$path" \
    "$commit" "$branch" "$dirty" <<'PY' || return 1
import datetime, json, sys

results, name, result, duration, destination, commit, branch, dirty = sys.argv[1:9]
try:
    with open(results) as handle:
        checks = json.load(handle)
except (FileNotFoundError, json.JSONDecodeError):
    checks = []

with open(destination, "w") as handle:
    json.dump({
        "gate": name,
        "result": result,
        "duration_ms": int(duration),
        "commit": commit,
        "branch": branch,
        "dirty": dirty == "true",
        "finished_at": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "checks": checks,
    }, handle, indent=2)
PY
}

# How many results actually reached the file. -1 when the file is unreadable,
# which is itself an answer: the gate cannot say what it ran.
gate_recorded_count() {
  python3 - "$GATE_RESULTS_FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
try:
    if not path or not os.path.exists(path):
        print(0)
    else:
        with open(path) as handle:
            print(len(json.load(handle)))
except Exception:
    print(-1)
PY
}

gate_finish() {
  local duration result recorded
  duration=$(( $(gate_now_ms) - GATE_STARTED_AT ))
  if [ "$GATE_FAILURES" -eq 0 ]; then result="pass"; else result="fail"; fi

  # The run has to account for itself before it is allowed to report. A gate that
  # recorded fewer results than it started was interrupted, and an interrupted
  # gate reporting PASS is the failure mode this whole file exists to prevent.
  recorded="$(gate_recorded_count)"
  if [ "$recorded" != "$GATE_EXPECTED_CHECKS" ]; then
    # Reported in the format that was asked for. A caller parsing JSON must get a
    # document saying the run failed, not prose on stderr it cannot read — an
    # unparseable answer is indistinguishable from no answer, and this is the one
    # message that must always arrive.
    if [ "$GATE_FORMAT" = "json" ]; then
      python3 - "$GATE_NAME" "$duration" "$recorded" "$GATE_EXPECTED_CHECKS" <<'PY'
import json, sys

name, duration, recorded, expected = sys.argv[1:5]
print(json.dumps({
    "gate": name,
    "result": "fail",
    "duration_ms": int(duration),
    "checks": [],
    "reason": f"recorded {recorded} of {expected} check result(s); "
              "the run was interrupted and proves nothing",
}, indent=2))
PY
    else
      printf '%s: FAIL — recorded %s of %s check result(s); the run was interrupted and proves nothing\n' \
        "$GATE_NAME" "$recorded" "$GATE_EXPECTED_CHECKS" >&2
    fi
    rm -f "$GATE_RESULTS_FILE"
    exit 1
  fi

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
