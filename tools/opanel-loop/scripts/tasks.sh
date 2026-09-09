#!/usr/bin/env bash
# tasks.sh <milestone-dir> <command> [args] — the only writer of tasks.json.
#
# Every status change in the loop goes through here so the invariants live in
# one place instead of in whatever the agent remembered to check. The one that
# matters most:
#
#   `set <id> done` is REFUSED unless review/<id>.md exists and its recorded
#   counts show Critical = 0 and High = 0.
#
# An agent asked whether its own work is finished says yes. DONE is the moment
# that optimism becomes a commit, so it is the moment that must be mechanical.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

require_jq

MDIR="$(milestone_dir_arg "${1:-}")"; shift || true
COMMAND="${1:-}"; shift || true
TASKS="$MDIR/tasks.json"
LOCK="$MDIR/.tasks"
[ -f "$TASKS" ] || die "no tasks.json in $MDIR"

STATES="pending ready in_progress review fix_required done blocked"

valid_state() {
  local candidate="$1" state
  for state in $STATES; do [ "$state" != "$candidate" ] || return 0; done
  return 1
}

story_exists() {
  [ "$(jq --arg id "$1" '[.stories[] | select(.id == $id)] | length' "$TASKS")" -gt 0 ]
}

# The next Story the loop may start: ready or pending, every dependsOn done,
# required ones first, then declaration order. Declaration order is the tie
# breaker on purpose — the pack orders Stories deliberately and a loop that
# reorders them silently is a loop that skipped the reasoning.
cmd_next() {
  jq -r '
    [ .stories[]
      | select(.status == "ready" or .status == "pending")
      | select([ .dependsOn[]? as $d
                 | ( [ $ROOT.stories[] | select(.id == $d) | .status ] | first ) == "done" ] | all)
    ]
    | sort_by(if .required then 0 else 1 end)
    | first // empty
    | .id
  ' --argjson ROOT "$(cat "$TASKS")" "$TASKS"
}

cmd_get() {
  local id="$1"
  story_exists "$id" || die "unknown story: $id"
  jq -c --arg id "$id" '.stories[] | select(.id == $id)' "$TASKS"
}

# Resolve .file against the milestone dir, then against stories/. The pack
# stores it relative to the milestone, but a hand-edited entry that names only
# the basename should not break the loop.
cmd_file() {
  local id="$1" rel
  story_exists "$id" || die "unknown story: $id"
  rel="$(jq -r --arg id "$id" '.stories[] | select(.id == $id) | .file // ""' "$TASKS")"
  [ -n "$rel" ] || die "story $id has no file"
  if [ -f "$MDIR/$rel" ]; then printf '%s\n' "$MDIR/$rel"
  elif [ -f "$MDIR/stories/$rel" ]; then printf '%s\n' "$MDIR/stories/$rel"
  else die "story file not found for $id: $rel"
  fi
}

review_counts_ok() {
  local id="$1" review="$MDIR/review/$1.md" line critical high
  [ -f "$review" ] || return 1
  # The Story review is markdown by template. Read the counts from the recorded
  # numbers rather than trusting a summary sentence: a table cell is checkable.
  critical="$(jq -r --arg id "$id" '.stories[] | select(.id == $id) | .review.critical // empty' "$TASKS")"
  high="$(jq -r --arg id "$id" '.stories[] | select(.id == $id) | .review.high // empty' "$TASKS")"
  [ -n "$critical" ] && [ -n "$high" ] || return 2
  [ "$critical" -eq 0 ] && [ "$high" -eq 0 ]
}

cmd_set() {
  local id="$1" state="$2" reason="${3:-}"
  story_exists "$id" || die "unknown story: $id"
  valid_state "$state" || die "invalid state: $state (valid: $STATES)"

  if [ "$state" = "done" ]; then
    if [ ! -f "$MDIR/review/$id.md" ]; then
      printf 'refusing done: %s has no review at %s\n' "$id" "$MDIR/review/$id.md" >&2
      exit 2
    fi
    set +e; review_counts_ok "$id"; local rc=$?; set -e
    if [ "$rc" -eq 2 ]; then
      printf 'refusing done: %s has no recorded review counts (run: tasks.sh %s review %s c h m l)\n' \
        "$id" "$MDIR" "$id" >&2
      exit 2
    fi
    if [ "$rc" -ne 0 ]; then
      printf 'refusing done: %s has Critical=%s High=%s; both must be 0\n' "$id" \
        "$(jq -r --arg id "$id" '.stories[]|select(.id==$id)|.review.critical' "$TASKS")" \
        "$(jq -r --arg id "$id" '.stories[]|select(.id==$id)|.review.high' "$TASKS")" >&2
      exit 2
    fi
  fi

  with_lock "$LOCK" write_json "$TASKS" \
    '(.stories[] | select(.id == $id) | .status) = $state
     | if $reason == "" then . else (.stories[] | select(.id == $id) | .reason) = $reason end' \
    --arg id "$id" --arg state "$state" --arg reason "$reason"
  printf '%s -> %s\n' "$id" "$state"
}

cmd_attempt() {
  local id="$1"
  story_exists "$id" || die "unknown story: $id"
  with_lock "$LOCK" write_json "$TASKS" \
    '(.stories[] | select(.id == $id) | .attempts) = ((.stories[] | select(.id == $id) | .attempts // 0) + 1)' \
    --arg id "$id"
  jq -r --arg id "$id" '.stories[] | select(.id == $id) | .attempts' "$TASKS"
}

cmd_review() {
  local id="$1" c="$2" h="$3" m="$4" l="$5"
  story_exists "$id" || die "unknown story: $id"
  case "$c$h$m$l" in *[!0-9]*) die "counts must be integers" ;; esac
  with_lock "$LOCK" write_json "$TASKS" \
    '(.stories[] | select(.id == $id) | .review) =
       {critical: ($c|tonumber), high: ($h|tonumber),
        medium: ($m|tonumber), low: ($l|tonumber)}' \
    --arg id "$id" --arg c "$c" --arg h "$h" --arg m "$m" --arg l "$l"
  printf '%s review: C=%s H=%s M=%s L=%s\n' "$id" "$c" "$h" "$m" "$l"
}

cmd_commit() {
  local id="$1" hash="$2"
  story_exists "$id" || die "unknown story: $id"
  with_lock "$LOCK" write_json "$TASKS" \
    '(.stories[] | select(.id == $id) | .commit) = $hash' \
    --arg id "$id" --arg hash "$hash"
  printf '%s commit: %s\n' "$id" "$hash"
}

cmd_milestone() {
  local state="$1"
  valid_state "$state" || die "invalid milestone state: $state"
  with_lock "$LOCK" write_json "$TASKS" '.status = $state' --arg state "$state"
  printf 'milestone -> %s\n' "$state"
}

cmd_remaining() {
  jq '[.stories[] | select(.status != "done" and .status != "blocked")] | length' "$TASKS"
}

cmd_active() {
  jq -r '[.stories[] | select(.status == "in_progress" or .status == "review" or .status == "fix_required")]
         | first // empty | .id' "$TASKS"
}

# run-start resets the per-run turn counter. The turn budget is a property of
# one autonomous run, not of the Milestone: a resumed run gets its own budget
# rather than inheriting an exhausted one.
cmd_run_start() {
  with_lock "$LOCK" write_json "$TASKS" \
    '.run = {startedAt: $now, turns: 0,
             doneAtStart: ([.stories[] | select(.status == "done")] | length)}' \
    --arg now "$(now_utc)"
  printf 'run started %s\n' "$(now_utc)"
}

cmd_turns() {
  case "${1:-get}" in
    get) jq -r '.run.turns // 0' "$TASKS" ;;
    increment|inc)
      with_lock "$LOCK" write_json "$TASKS" '.run.turns = ((.run.turns // 0) + 1)'
      jq -r '.run.turns' "$TASKS" ;;
    *) die "usage: turns [get|increment]" ;;
  esac
}

case "$COMMAND" in
  next)      cmd_next ;;
  get)       [ $# -ge 1 ] || die "usage: get <id>"; cmd_get "$1" ;;
  file)      [ $# -ge 1 ] || die "usage: file <id>"; cmd_file "$1" ;;
  set)       [ $# -ge 2 ] || die "usage: set <id> <status> [reason]"; cmd_set "$1" "$2" "${3:-}" ;;
  attempt)   [ $# -ge 1 ] || die "usage: attempt <id>"; cmd_attempt "$1" ;;
  review)    [ $# -ge 5 ] || die "usage: review <id> <c> <h> <m> <l>"; cmd_review "$1" "$2" "$3" "$4" "$5" ;;
  commit)    [ $# -ge 2 ] || die "usage: commit <id> <hash>"; cmd_commit "$1" "$2" ;;
  milestone) [ $# -ge 1 ] || die "usage: milestone <status>"; cmd_milestone "$1" ;;
  remaining) cmd_remaining ;;
  active)    cmd_active ;;
  run-start) cmd_run_start ;;
  turns)     cmd_turns "${1:-get}" ;;
  *) die "unknown command: ${COMMAND:-<none>}
usage: tasks.sh <milestone-dir> {next|get|file|set|attempt|review|commit|milestone|remaining|active|run-start|turns}" ;;
esac
