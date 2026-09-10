#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protects the files a loop must not be able to edit
# its way past.
#
# The rule behind the deny list: a gate is not editable to make a Story pass
# (AGENT_RULES, "Quality Gates"). Neither is the architecture the gate defends.
# If the loop could edit bin/stop-gate, every other check in this plugin would
# be advisory.
#
# The ask list is for files that are legitimately edited by some Stories and
# catastrophic when edited by the wrong one — a lint config, a workflow, a
# migration that already ran.

set -uo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)"
[ -n "$FILE" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REL="${FILE#"$ROOT"/}"

decide() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
  exit 0
}

matches() { printf '%s' "$REL" | grep -Eq "$1"; }

# Outside an autonomous run, gate maintenance is ordinary human-directed work.
# The ordinary host permission flow applies; active builders cannot edit
# their judges. No extra permission prompt is added by this plugin.
if [ ! -f "$ROOT/.backlog-active" ] && matches '^bin/(gate|stop-gate|merge-gate)|^lib/gates/|^tools/opanel-loop/'; then
  exit 0
fi

# --- deny: approved specification and the gates themselves -----------------
matches '^docs/architecture/' \
  && decide deny "docs/architecture/** is approved architecture. A change at this level needs an ADR in docs/decisions/, not an edit."
matches '^docs/AGENT_RULES\.md$' \
  && decide deny "docs/AGENT_RULES.md is the normative rule set. Editing the rules to fit the implementation inverts the precedence order."
matches '^docs/MASTER\.md$' \
  && decide deny "docs/MASTER.md is the map of the specification. Keep it accurate through its own change, not through a Story."
matches '^docs/annexes/' \
  && decide deny "docs/annexes/** is normative. A divergence is recorded in SPEC_CONFLICTS.md, never resolved by rewriting the annex."
matches '^bin/(gate|stop-gate|merge-gate)' \
  && decide deny "This is a quality gate. Failing a gate means fixing the implementation — a gate edited to pass protects nothing."
matches '^lib/gates/' \
  && decide deny "lib/gates/** implements the gates. Changing a checker to get green needs its own Story or ADR."
matches '^config/credentials|master\.key$|^\.env' \
  && decide deny "Credentials. No production credential should exist in this workspace at all."

matches '^tools/opanel-loop/' \
  && decide deny "The running loop cannot edit its own hooks, skills or agents. Perform authorized maintenance outside the backlog run."

# --- ask: legitimately editable, occasionally disastrous -------------------
matches '^\.rubocop\.yml$|eslint\.config\.(js|ts|mjs)$|^\.eslintrc' \
  && decide ask "Lint configuration. Relaxing a rule to pass a check is a weakened gate — say which Story or waiver authorises it."
matches '^\.github/workflows/' \
  && decide ask "CI workflow. This decides what runs on every commit."
matches '^(\.github/)?CODEOWNERS$' \
  && decide ask "CODEOWNERS decides who must review protected paths."

if printf '%s' "$REL" | grep -Eq '^db/migrate/'; then
  [ ! -e "$FILE" ] || decide ask "This migration already exists. Editing an applied migration breaks expand-contract; write a new one instead."
fi

exit 0
