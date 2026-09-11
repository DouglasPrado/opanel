#!/usr/bin/env bash
# Stop hook — the per-turn state machine of the Milestone loop (Annex H §4.2).
#
# The loop cannot rely on the agent deciding it is finished: "an agent asked
# whether its work is finished will say yes". So stopping is a decision this
# script makes from the recorded state, and every branch either blocks the stop
# with a concrete next action or stops deliberately.
#
#   block  -> {"decision":"block","reason":"..."} on stdout, exit 0
#   stop   -> remove .backlog-active, exit 0
#
# Nothing here runs unless .backlog-active exists, so a normal interactive
# session is never touched by it.

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ACTIVE="$ROOT/.backlog-active"
[ -f "$ACTIVE" ] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TASKS_SH="$PLUGIN_ROOT/scripts/tasks.sh"
STATE_SH="$PLUGIN_ROOT/scripts/review-state.sh"

MDIR="$(head -n1 "$ACTIVE" | tr -d '[:space:]')"
case "$MDIR" in /*) ;; *) MDIR="$ROOT/$MDIR" ;; esac

# --- whose run is this? -----------------------------------------------------
# Line 2 of .backlog-active is the session id of the run's owner. A session that
# is not the owner is a bystander in the same repository, and driving it through
# the loop is worse than useless: on 2026-09-10 an interactive session was told
# "Story M01-11 is still open. Close it" dozens of times while the autopilot's
# own session was writing that exact Story. Two writers, one tasks.json.
#
# Unowned runs — a .backlog-active written before this line existed — are left
# alone rather than adopted, so an upgrade mid-run does not silently hand the
# loop to whoever stops first.
OWNER="$(sed -n '2p' "$ACTIVE" | tr -d '[:space:]')"
ME="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -n "$OWNER" ] && [ -n "$ME" ] && [ "$OWNER" != "$ME" ]; then
  exit 0
fi

stop_now() { rm -f "$ACTIVE"; exit 0; }

block() {
  # jq keeps the reason valid JSON no matter what it contains.
  jq -nc --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

if [ ! -d "$MDIR" ] || [ ! -f "$MDIR/tasks.json" ]; then
  block "'.backlog-active' points at '$MDIR', which has no tasks.json. Fix the path or delete .backlog-active."
fi

command -v jq >/dev/null 2>&1 || stop_now
MILESTONE="$(basename "$MDIR")"

# --- turn budget -----------------------------------------------------------
# Six turns per Story plus thirty for the review and fix phases. This is the
# backstop for a loop that is progressing in appearance only; hitting it is a
# defect to read, not a threshold to raise.
TURNS="$(bash "$TASKS_SH" "$MDIR" turns increment 2>/dev/null || echo 0)"
STORIES="$(jq '.stories | length' "$MDIR/tasks.json" 2>/dev/null || echo 0)"
LIMIT=$((STORIES * 6 + 30))
if [ "$TURNS" -gt "$LIMIT" ]; then
  bash "$STATE_SH" "$MDIR" block TURN_LIMIT_EXCEEDED >/dev/null 2>&1 || true
  stop_now
fi

STATUS="$(bash "$STATE_SH" "$MDIR" status 2>/dev/null || echo implementing)"
BLOCK_REASON="$(jq -r '.blockedReason // ""' "$MDIR/review-state.json" 2>/dev/null || true)"

case "$STATUS" in
  # ADR-0007 — none of these branches ends the run waiting for a person.
  #
  # The one exception is a Milestone the arbiter itself ruled BLOCK on: asking
  # the same question of the same evidence again is the infinite loop this
  # script exists to prevent.
  blocked)
    # Prefix, not equality: the arbiter records why it blocked, so the reason
    # reads "ARBITER_BLOCK — <what is missing>" and never equals the code.
    case "$BLOCK_REASON" in
      ARBITER_BLOCK_NEEDS_ADR*)
        # Blocked on a decision nobody has written down. That is work an agent
        # can do, so the chain does not end here: the adr-author writes it, and
        # the human reads it in the Milestone's Pull Request like every other
        # autonomous decision.
        block "$MILESTONE is blocked on a decision that does not exist yet ($BLOCK_REASON). Dispatch the adr-author agent in a fresh context with the arbiter's entry in $MDIR/DECISIONS.md and the evidence it cites. Write what it returns to docs/decisions/ADR-<NNNN>-<slug>.md with the next free number, then run review-state.sh $MDIR adr-written docs/decisions/<file>. If it returns ALREADY DECIDED or NEEDS HUMAN, record that in DECISIONS.md and do not write an ADR."
        ;;
      ARBITER_BLOCK*)
        stop_now
        ;;
    esac
    block "The Milestone is blocked ($BLOCK_REASON). Under ADR-0007 that is an arbitration, not a stop: dispatch the arbiter agent in a fresh context with the recorded reason and the evidence behind it, append its decision verbatim to $MDIR/DECISIONS.md, then run review-state.sh $MDIR arbitrate."
    ;;
  # ACCEPTED landed here. The arbiter releases the Milestone now, not a human.
  human_acceptance)
    block "The Milestone verdict is ACCEPTED and waiting to be released. Dispatch the arbiter agent to confirm the counts, the commit and MILESTONE_REPORT.md, append its decision to $MDIR/DECISIONS.md, then run review-state.sh $MDIR arbitrate."
    ;;
  # Released. Ship the Pull Request, then chain to the next Milestone.
  accepted)
    block "$MILESTONE is accepted. Open its stacked Pull Request with 'bin/milestone-pr $MILESTONE', then continue the chain with /autopilot. Do not merge anything."
    ;;
  ready_for_review)
    block "M00 handoff: the Milestone is ready_for_review. Run /review-milestone $MDIR now. Do not implement anything else."
    ;;
  reviewing)
    block "A Milestone review is in progress. Finish it and record the verdict with review-state.sh $MDIR verdict <ACCEPTED|NOT_ACCEPTED> <c> <h> <m> <l>."
    ;;
  fix_required)
    block "The independent review returned NOT_ACCEPTED. Run /fix-milestone $MDIR and correct only the Critical and High findings."
    ;;
  fixing)
    block "A fix phase is in progress. Finish the blocking findings, write FIX_REPORT_<NN>.md, then run review-state.sh $MDIR fix-done."
    ;;
esac

# --- implementing ----------------------------------------------------------
ACTIVE_STORY="$(bash "$TASKS_SH" "$MDIR" active 2>/dev/null || true)"
if [ -n "$ACTIVE_STORY" ]; then
  block "Story $ACTIVE_STORY is still open. Close it — review, counts, done, commit — before starting anything else."
fi

# A checkpoint is a legitimate reason to stop: the run did the work it was
# budgeted for and the state is clean between Stories.
MAX_PER_RUN="${OPANEL_MAX_STORIES_PER_RUN:-0}"
if [ "$MAX_PER_RUN" -gt 0 ]; then
  # Counted against the baseline `run-start` recorded, not against every Story
  # the Milestone ever closed. The first version read `startedAt` and then
  # counted all `done` stories anyway, so a Milestone with work already behind it
  # stopped immediately — the flag did not do what its name says.
  BASELINE="$(jq -r '.run.doneAtStart // 0' "$MDIR/tasks.json" 2>/dev/null || echo 0)"
  DONE_NOW="$(jq '[.stories[] | select(.status == "done")] | length' "$MDIR/tasks.json" 2>/dev/null || echo 0)"
  if [ "$((DONE_NOW - BASELINE))" -ge "$MAX_PER_RUN" ]; then
    stop_now
  fi
fi

NEXT="$(bash "$TASKS_SH" "$MDIR" next 2>/dev/null || true)"
if [ -n "$NEXT" ]; then
  block "Next Story: $NEXT. Mark it in_progress, record the attempt, and open a task titled exactly '$NEXT: <title>'."
fi

REMAINING="$(bash "$TASKS_SH" "$MDIR" remaining 2>/dev/null || echo 0)"
BLOCKED_REQUIRED="$(jq -r '[.stories[] | select(.required == true and .status == "blocked")] | length' "$MDIR/tasks.json")"

if [ "$BLOCKED_REQUIRED" -gt 0 ]; then
  IDS="$(jq -r '[.stories[] | select(.required == true and .status == "blocked") | .id] | join(", ")' "$MDIR/tasks.json")"
  block "Required Stories are blocked: $IDS. Under ADR-0007 this is an arbitration. Dispatch the arbiter agent for each, append its decision to $MDIR/DECISIONS.md, and act on the verdict — FIX reopens the Story for one bounded round, DEBT defers it to the Milestone the arbiter names."
fi

if [ "$REMAINING" -gt 0 ]; then
  block "$REMAINING Stories remain but none is ready. Record why in BLOCKERS.md with a reproducible diagnosis, then dispatch the arbiter agent to decide what the run does about it and append its decision to $MDIR/DECISIONS.md."
fi

# --- closing the Milestone -------------------------------------------------
GATE_OUT="$(cd "$ROOT" && bin/stop-gate "$MILESTONE" 2>/dev/null || true)"
GATE_OK="$(printf '%s' "$GATE_OUT" | jq -r '.ok // false' 2>/dev/null || echo false)"

if [ "$GATE_OK" != "true" ]; then
  REASON="$(printf '%s' "$GATE_OUT" | jq -r '[.checks[]? | select(.result != "pass") | .name] | join(", ")' 2>/dev/null || true)"
  [ -n "$REASON" ] || REASON="see bin/stop-gate $MILESTONE"
  block "bin/stop-gate $MILESTONE is not ok ($REASON). Fix what it names and generate MILESTONE_REPORT.md with 'Status: READY_FOR_REVIEW'. If you have already tried and the same check is still red, do not try a third time — dispatch the arbiter agent with the gate's output and append its decision to $MDIR/DECISIONS.md."
fi

bash "$STATE_SH" "$MDIR" set ready_for_review >/dev/null 2>&1 || true
block "Every Story is done and bin/stop-gate $MILESTONE is ok. Next turn: run /review-milestone $MDIR."
