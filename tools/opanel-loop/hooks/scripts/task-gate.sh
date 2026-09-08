#!/usr/bin/env bash
# TaskCompleted — a task named after a Story may not be closed while that Story
# is still open in tasks.json.
#
# The task list and tasks.json are two records of the same work, and the one
# that survives the session is tasks.json. Closing the task first is how a
# Story silently becomes "finished" without a review, counts or a commit.

set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ACTIVE="$ROOT/.backlog-active"
[ -f "$ACTIVE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
TITLE="$(printf '%s' "$INPUT" | jq -r '.task.title // .tool_input.title // ""' 2>/dev/null || true)"
ID="$(printf '%s' "$TITLE" | grep -oE 'M[0-9]{2}-[0-9]{2}' | head -1 || true)"
[ -n "$ID" ] || exit 0

MDIR="$(head -n1 "$ACTIVE" | tr -d '[:space:]')"
case "$MDIR" in /*) ;; *) MDIR="$ROOT/$MDIR" ;; esac
[ -f "$MDIR/tasks.json" ] || exit 0

STATUS="$(jq -r --arg id "$ID" '.stories[] | select(.id == $id) | .status' "$MDIR/tasks.json" 2>/dev/null || true)"
[ -n "$STATUS" ] || exit 0

if [ "$STATUS" != "done" ] && [ "$STATUS" != "blocked" ]; then
  printf 'Story %s is %s in tasks.json, not done or blocked.\n' "$ID" "$STATUS" >&2
  printf 'Close the Story first: independent review, tasks.sh review %s c h m l, tasks.sh set %s done, then commit.\n' "$ID" "$ID" >&2
  exit 2
fi
exit 0
