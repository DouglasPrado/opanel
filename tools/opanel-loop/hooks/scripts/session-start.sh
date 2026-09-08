#!/usr/bin/env bash
# SessionStart — rebuild state from the repository, never from memory.
#
# CLAUDE.md's Context Recovery says a new session reconstructs state from git
# and the Implementation Pack. This puts the cheap half of that in front of the
# agent immediately, so a resumed run does not start by guessing where it was.

set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

CONTEXT="branch: $(git branch --show-current 2>/dev/null || echo '(detached)')

recent commits:
$(git log --oneline -5 2>/dev/null || echo '(no history)')"

ACTIVE="$ROOT/.backlog-active"
if [ -f "$ACTIVE" ] && command -v jq >/dev/null 2>&1; then
  MDIR="$(head -n1 "$ACTIVE" | tr -d '[:space:]')"
  case "$MDIR" in /*) ;; *) MDIR="$ROOT/$MDIR" ;; esac
  if [ -f "$MDIR/tasks.json" ]; then
    COUNTS="$(jq -r '[.stories[].status] | group_by(.) | map("\(.[0]): \(length)") | join("  ")' "$MDIR/tasks.json" 2>/dev/null)"
    RSTATUS="$(jq -r '.status' "$MDIR/review-state.json" 2>/dev/null || echo 'n/a')"
    CONTEXT="$CONTEXT

AUTONOMOUS RUN ACTIVE — milestone $(basename "$MDIR")
stories: $COUNTS
review-state: $RSTATUS

Read $MDIR/GOAL.md and the current Story before acting. The Stop hook decides
what happens next; follow the instruction it returns."
  fi
fi

jq -nc --arg c "$CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}'
