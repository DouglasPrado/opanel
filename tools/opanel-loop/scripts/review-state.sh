#!/usr/bin/env bash
# review-state.sh <milestone-dir> <command> [args] — the only writer of
# review-state.json, keeping it valid against scripts/schemas/review-state.schema.json.
#
# The verdict is the one field an implementer must never be able to set by
# accident, so the transitions are encoded here rather than described in a
# prompt: ACCEPTED demands Critical = 0 and High = 0, NOT_ACCEPTED demands at
# least one of them, and an ACCEPTED verdict lands on human_acceptance — never
# on "done". No path in this script reaches human_acceptance without a verdict.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

require_jq

MDIR="$(milestone_dir_arg "${1:-}")"; shift || true
COMMAND="${1:-}"; shift || true
STATE="$MDIR/review-state.json"
LOCK="$MDIR/.review-state"
MILESTONE="$(milestone_id_from_dir "$MDIR")"

STATUSES="implementing ready_for_review reviewing fix_required fixing accepted blocked human_acceptance"

valid_status() {
  local candidate="$1" status
  for status in $STATUSES; do [ "$status" != "$candidate" ] || return 0; done
  return 1
}

need_state() { [ -f "$STATE" ] || die "no review-state.json in $MDIR (run: review-state.sh $MDIR init)"; }
current() { jq -r '.status' "$STATE"; }
touch_now() { printf '%s' "$(now_utc)"; }

cmd_init() {
  if [ -f "$STATE" ]; then printf '%s\n' "$(current)"; return 0; fi
  case "$MILESTONE" in M[0-9][0-9]) ;; *) die "milestone dir must be named M<NN>: $MDIR" ;; esac
  cat > "$STATE" <<JSON
{
  "milestone": "$MILESTONE",
  "status": "implementing",
  "reviewAttempt": 0,
  "fixAttempt": 0,
  "executionFailures": 0,
  "maxReviewAttempts": 3,
  "maxFixAttempts": 3,
  "lastReviewer": null,
  "verdict": null,
  "criticalCount": null,
  "highCount": null,
  "mediumCount": null,
  "lowCount": null,
  "lastError": null,
  "blockedReason": null,
  "acceptedAt": null,
  "updatedAt": "$(now_utc)"
}
JSON
  printf 'initialised %s\n' "$STATE"
}

cmd_status() { need_state; current; }

cmd_set() {
  need_state
  local status="$1"
  valid_status "$status" || die "invalid status: $status"
  with_lock "$LOCK" write_json "$STATE" \
    '.status = $s | .updatedAt = $now' --arg s "$status" --arg now "$(touch_now)"
  printf '%s\n' "$status"
}

cmd_review_start() {
  need_state
  local attempt max
  attempt="$(jq -r '.reviewAttempt' "$STATE")"
  max="$(jq -r '.maxReviewAttempts' "$STATE")"
  if [ "$attempt" -ge "$max" ]; then
    with_lock "$LOCK" write_json "$STATE" \
      '.status = "blocked" | .blockedReason = "REVIEW_ATTEMPTS_EXHAUSTED"
       | .lastError = "REVIEW_ATTEMPTS_EXHAUSTED" | .updatedAt = $now' \
      --arg now "$(touch_now)"
    printf 'review attempts exhausted (%s/%s); milestone blocked\n' "$attempt" "$max" >&2
    exit 2
  fi
  with_lock "$LOCK" write_json "$STATE" \
    '.status = "reviewing" | .reviewAttempt += 1 | .lastReviewer = "claude"
     | .verdict = null | .criticalCount = null | .highCount = null
     | .mediumCount = null | .lowCount = null
     | .lastError = null | .blockedReason = null | .updatedAt = $now' \
    --arg now "$(touch_now)"
  jq -r '.reviewAttempt' "$STATE"
}

cmd_verdict() {
  need_state
  local verdict="$1" c="$2" h="$3" m="$4" l="$5"
  case "$c$h$m$l" in *[!0-9]*) die "counts must be integers" ;; esac
  case "$verdict" in
    ACCEPTED)
      { [ "$c" -eq 0 ] && [ "$h" -eq 0 ]; } || die "ACCEPTED requires Critical=0 and High=0 (got C=$c H=$h)" ;;
    NOT_ACCEPTED)
      [ $((c + h)) -ge 1 ] || die "NOT_ACCEPTED requires at least one Critical or High finding" ;;
    *) die "verdict must be ACCEPTED or NOT_ACCEPTED" ;;
  esac

  local next
  if [ "$verdict" = "ACCEPTED" ]; then next="human_acceptance"; else next="fix_required"; fi

  with_lock "$LOCK" write_json "$STATE" \
    '.verdict = $v | .criticalCount = ($c|tonumber) | .highCount = ($h|tonumber)
     | .mediumCount = ($m|tonumber) | .lowCount = ($l|tonumber)
     | .lastReviewer = "claude" | .status = $next
     | .executionFailures = 0
     | (if $v == "ACCEPTED" then .acceptedAt = $now else . end)
     | .updatedAt = $now' \
    --arg v "$verdict" --arg c "$c" --arg h "$h" --arg m "$m" --arg l "$l" \
    --arg next "$next" --arg now "$(touch_now)"
  printf '%s -> %s\n' "$verdict" "$next"
}

cmd_fix_start() {
  need_state
  local attempt max
  attempt="$(jq -r '.fixAttempt' "$STATE")"
  max="$(jq -r '.maxFixAttempts' "$STATE")"
  if [ "$attempt" -ge "$max" ]; then
    with_lock "$LOCK" write_json "$STATE" \
      '.status = "blocked" | .blockedReason = "FIX_ATTEMPTS_EXHAUSTED"
       | .lastError = "FIX_ATTEMPTS_EXHAUSTED" | .updatedAt = $now' \
      --arg now "$(touch_now)"
    printf 'fix attempts exhausted (%s/%s); milestone blocked\n' "$attempt" "$max" >&2
    exit 2
  fi
  with_lock "$LOCK" write_json "$STATE" \
    '.status = "fixing" | .fixAttempt += 1 | .lastError = null | .updatedAt = $now' \
    --arg now "$(touch_now)"
  jq -r '.fixAttempt' "$STATE"
}

# The fix hands the Milestone back for review and clears the previous verdict.
# Leaving stale counts behind would let a later reader mistake the answered
# review for the current state of the Milestone.
cmd_fix_done() {
  need_state
  with_lock "$LOCK" write_json "$STATE" \
    '.status = "ready_for_review" | .verdict = null
     | .criticalCount = null | .highCount = null
     | .mediumCount = null | .lowCount = null
     | .lastError = null | .blockedReason = null | .updatedAt = $now' \
    --arg now "$(touch_now)"
  printf 'ready_for_review\n'
}

cmd_block() {
  need_state
  local reason="$1"
  [ -n "$reason" ] || die "usage: block <reason>"
  with_lock "$LOCK" write_json "$STATE" \
    '.status = "blocked" | .blockedReason = $r | .lastError = $r | .updatedAt = $now' \
    --arg r "$reason" --arg now "$(touch_now)"
  printf 'blocked: %s\n' "$reason"
}

# An execution failure is not a verdict. It records what broke and counts it,
# but never spends a review or fix attempt: the budget exists to stop a
# review/fix loop, not to punish a CLI that died.
cmd_error() {
  need_state
  local code="$1"
  [ -n "$code" ] || die "usage: error <code>"
  with_lock "$LOCK" write_json "$STATE" \
    '.lastError = $c | .executionFailures = ((.executionFailures // 0) + 1) | .updatedAt = $now' \
    --arg c "$code" --arg now "$(touch_now)"
  printf 'error: %s (executionFailures=%s)\n' "$code" "$(jq -r '.executionFailures' "$STATE")"
}

cmd_attempt_number() {
  need_state
  printf '%02d\n' "$(jq -r '.reviewAttempt' "$STATE")"
}

case "$COMMAND" in
  init)           cmd_init ;;
  status)         cmd_status ;;
  set)            [ $# -ge 1 ] || die "usage: set <status>"; cmd_set "$1" ;;
  review-start)   cmd_review_start ;;
  verdict)        [ $# -ge 5 ] || die "usage: verdict <ACCEPTED|NOT_ACCEPTED> <c> <h> <m> <l>"
                  cmd_verdict "$1" "$2" "$3" "$4" "$5" ;;
  fix-start)      cmd_fix_start ;;
  fix-done)       cmd_fix_done ;;
  block)          [ $# -ge 1 ] || die "usage: block <reason>"; cmd_block "$1" ;;
  error)          [ $# -ge 1 ] || die "usage: error <code>"; cmd_error "$1" ;;
  attempt-number) cmd_attempt_number ;;
  *) die "unknown command: ${COMMAND:-<none>}
usage: review-state.sh <milestone-dir> {init|status|set|review-start|verdict|fix-start|fix-done|block|error|attempt-number}" ;;
esac
