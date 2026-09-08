#!/usr/bin/env bash
# PreToolUse(Bash) — refuses the Dangerous Actions of CLAUDE.md, and asks before
# anything that reaches real infrastructure or looks like a weakened gate.
#
# Two decisions, deliberately different:
#   deny — destructive or irreversible against real state, or an action CLAUDE.md
#          lists as needing a human gate. No autonomous run has a reason for it.
#   ask  — plausibly legitimate but consequential enough that a human should see
#          it. Suppressions live here: `rubocop:disable` is sometimes right, and
#          "make a test pass by disabling the rule" is exactly how a gate rots.
#
# This is a guard, not a security boundary: it reads the command string, and a
# determined bypass is always possible. It exists to stop the accident.

set -uo pipefail

INPUT="$(cat)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$COMMAND" ] || exit 0

decide() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
  exit 0
}

matches() { printf '%s' "$COMMAND" | grep -Eqi "$1"; }

# --- deny: CLAUDE.md Dangerous Actions -------------------------------------
matches '(^|[^[:alnum:]])git[[:space:]]+push([[:space:]]|$).*(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))' \
  && decide deny "Force push. CLAUDE.md forbids force-pushing; a protected branch is never rewritten by the loop."
matches '(^|[^[:alnum:]])git[[:space:]]+push([[:space:]]|$).*(origin[[:space:]]+)?(main|master)([[:space:]]|$)' \
  && decide deny "Push to main/master. The loop commits on its own branch; merging is a human decision."
matches 'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR])[[:space:]]+/([[:space:]]|$)' \
  && decide deny "rm -rf / — destructive and irreversible."
matches 'db:(drop|reset|schema:load)' \
  && decide deny "Destructive database operation. CLAUDE.md requires an explicit human gate for this."
matches 'DROP[[:space:]]+(TABLE|DATABASE)' \
  && decide deny "DROP TABLE/DATABASE. Schema removal happens in a contract-phase migration, never ad hoc."
matches 'force-new-cluster' \
  && decide deny "force-new-cluster rebuilds Swarm quorum from one node. Human gate only (RB-06)."
matches 'swarm[[:space:]]+leave.*--force' \
  && decide deny "swarm leave --force removes a node from the cluster destructively."
matches 'docker[[:space:]]+system[[:space:]]+prune' \
  && decide deny "docker system prune deletes state the reconcilers treat as Actual State."
matches 'RAILS_ENV=production|RACK_ENV=production' \
  && decide deny "Production environment. No production credential or environment belongs in this workspace."

# --- ask: real infrastructure ----------------------------------------------
matches 'docker[[:space:]]+(stack|service|secret|network)[[:space:]]+rm' \
  && decide ask "Removes a Docker resource the platform may own. Confirm this targets the lab and not a real cluster."
matches '(^|[^[:alnum:]])terraform([[:space:]]|$)' \
  && decide ask "Terraform changes real infrastructure."
matches '(^|[^[:alnum:]])kubectl([[:space:]]|$)' \
  && decide ask "kubectl reaches a cluster outside the approved runtime."
matches '(^|[^[:alnum:]])(certbot|traefik)([[:space:]]|$)' \
  && decide ask "Touches certificates or the edge; a mistake here takes sites down."
matches '(^|[^[:alnum:]])(dig|nsupdate|cli53|route53)([[:space:]]|$)|dns[[:space:]]+(record|update|delete)' \
  && decide ask "Touches DNS. Modifying DNS is a human-gated action."

# --- ask: a gate being weakened --------------------------------------------
matches 'rubocop:disable|eslint-disable|--no-verify|(^|[^[:alnum:]])xit\(|(^|[^[:alnum:]])xdescribe|\.skip\(' \
  && decide ask "This looks like a suppressed check or a skipped test. A failing test is fixed in the implementation, never silenced — say which Story or waiver authorises it."

exit 0
