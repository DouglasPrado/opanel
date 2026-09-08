#!/usr/bin/env bash
# Exercises the plugin's state machine against a throwaway copy of a real
# milestone. Nothing here touches the repository's own state.
#
# The cases worth having are the refusals: `done` without a review, ACCEPTED
# with findings, a task closed over an open Story, an edit to bin/stop-gate. A
# gate that only proves the happy path proves nothing about a gate.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
TASKS="$PLUGIN_ROOT/scripts/tasks.sh"
STATE="$PLUGIN_ROOT/scripts/review-state.sh"

PASS=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok()   { PASS=$((PASS + 1)); printf '  ok  %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || fail "jq is required"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/opanel-loop-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

MDIR="$TMP/M01"
mkdir -p "$MDIR/stories" "$MDIR/review"
cp "$REPO_ROOT/docs/implementation/M01/tasks.json" "$MDIR/tasks.json"
FIRST="$(jq -r '.stories[0].id' "$MDIR/tasks.json")"
touch "$MDIR/stories/$(jq -r '.stories[0].file' "$MDIR/tasks.json" | sed 's#^stories/##')"

printf '== tasks.sh\n'

[ "$(bash "$TASKS" "$MDIR" next)" = "$FIRST" ] || fail "next should return $FIRST"
ok "next returns the first ready Story"

bash "$TASKS" "$MDIR" set "$FIRST" in_progress >/dev/null || fail "set in_progress"
[ "$(jq -r --arg i "$FIRST" '.stories[]|select(.id==$i)|.status' "$MDIR/tasks.json")" = "in_progress" ] \
  || fail "status was not written"
ok "set writes a valid state"

[ "$(bash "$TASKS" "$MDIR" active)" = "$FIRST" ] || fail "active should report $FIRST"
ok "active reports the open Story"

bash "$TASKS" "$MDIR" file "$FIRST" >/dev/null || fail "file should resolve the Story path"
ok "file resolves the Story path"

# The central refusal: done is unreachable without a review on disk.
if bash "$TASKS" "$MDIR" set "$FIRST" done >/dev/null 2>&1; then
  fail "done was accepted with no review file"
fi
ok "done is refused without review/<id>.md"

printf '# review\nCOUNTS 0 0 1 2\n' > "$MDIR/review/$FIRST.md"
if bash "$TASKS" "$MDIR" set "$FIRST" done >/dev/null 2>&1; then
  fail "done was accepted with no recorded counts"
fi
ok "done is refused with no recorded counts"

bash "$TASKS" "$MDIR" review "$FIRST" 1 0 0 0 >/dev/null || fail "review should record counts"
if bash "$TASKS" "$MDIR" set "$FIRST" done >/dev/null 2>&1; then
  fail "done was accepted with Critical=1"
fi
ok "done is refused while Critical > 0"

bash "$TASKS" "$MDIR" review "$FIRST" 0 2 0 0 >/dev/null
if bash "$TASKS" "$MDIR" set "$FIRST" done >/dev/null 2>&1; then
  fail "done was accepted with High=2"
fi
ok "done is refused while High > 0"

bash "$TASKS" "$MDIR" review "$FIRST" 0 0 3 4 >/dev/null
bash "$TASKS" "$MDIR" set "$FIRST" done >/dev/null || fail "done should be allowed at C=0 H=0"
ok "done is allowed once Critical = High = 0"

bash "$TASKS" "$MDIR" commit "$FIRST" deadbee >/dev/null
[ "$(jq -r --arg i "$FIRST" '.stories[]|select(.id==$i)|.commit' "$MDIR/tasks.json")" = "deadbee" ] \
  || fail "commit hash was not recorded"
ok "commit records the hash"

[ "$(bash "$TASKS" "$MDIR" attempt "$FIRST")" = "1" ] || fail "attempt should increment to 1"
ok "attempt increments"

bash "$TASKS" "$MDIR" run-start >/dev/null
[ "$(bash "$TASKS" "$MDIR" turns)" = "0" ] || fail "run-start should reset turns"
[ "$(bash "$TASKS" "$MDIR" turns increment)" = "1" ] || fail "turns should increment"
ok "run-start resets and turns increments"

if bash "$TASKS" "$MDIR" set "$FIRST" nonsense >/dev/null 2>&1; then
  fail "an invalid state was accepted"
fi
ok "an invalid state is refused"

printf '== review-state.sh\n'

bash "$STATE" "$MDIR" init >/dev/null || fail "init"
[ "$(bash "$STATE" "$MDIR" status)" = "implementing" ] || fail "init should start implementing"
ok "init creates a valid state"

python3 - "$MDIR/review-state.json" "$REPO_ROOT/scripts/schemas/review-state.schema.json" <<'PY' || fail "state does not satisfy the schema"
import json, sys
state = json.load(open(sys.argv[1])); schema = json.load(open(sys.argv[2]))
missing = [k for k in schema["required"] if k not in state]
assert not missing, missing
assert state["status"] in schema["properties"]["status"]["enum"]
PY
ok "the written state satisfies review-state.schema.json"

[ "$(bash "$STATE" "$MDIR" review-start)" = "1" ] || fail "review-start should return attempt 1"
[ "$(bash "$STATE" "$MDIR" status)" = "reviewing" ] || fail "review-start should set reviewing"
[ "$(bash "$STATE" "$MDIR" attempt-number)" = "01" ] || fail "attempt-number should be zero padded"
ok "review-start opens attempt 01"

if bash "$STATE" "$MDIR" verdict ACCEPTED 1 0 0 0 >/dev/null 2>&1; then
  fail "ACCEPTED was allowed with Critical=1"
fi
ok "ACCEPTED is refused with findings"

if bash "$STATE" "$MDIR" verdict NOT_ACCEPTED 0 0 3 1 >/dev/null 2>&1; then
  fail "NOT_ACCEPTED was allowed with no Critical or High"
fi
ok "NOT_ACCEPTED is refused without a blocking finding"

bash "$STATE" "$MDIR" verdict NOT_ACCEPTED 1 2 0 0 >/dev/null || fail "verdict NOT_ACCEPTED"
[ "$(bash "$STATE" "$MDIR" status)" = "fix_required" ] || fail "NOT_ACCEPTED should reach fix_required"
ok "NOT_ACCEPTED reaches fix_required"

[ "$(bash "$STATE" "$MDIR" fix-start)" = "1" ] || fail "fix-start should return attempt 1"
[ "$(bash "$STATE" "$MDIR" status)" = "fixing" ] || fail "fix-start should set fixing"
bash "$STATE" "$MDIR" fix-done >/dev/null
[ "$(bash "$STATE" "$MDIR" status)" = "ready_for_review" ] || fail "fix-done should set ready_for_review"
[ "$(jq -r '.verdict' "$MDIR/review-state.json")" = "null" ] || fail "fix-done should clear the verdict"
ok "the fix cycle returns to ready_for_review and clears the verdict"

bash "$STATE" "$MDIR" review-start >/dev/null
bash "$STATE" "$MDIR" verdict ACCEPTED 0 0 1 2 >/dev/null || fail "verdict ACCEPTED"
[ "$(bash "$STATE" "$MDIR" status)" = "human_acceptance" ] || fail "ACCEPTED should reach human_acceptance"
[ "$(jq -r '.acceptedAt' "$MDIR/review-state.json")" != "null" ] || fail "acceptedAt should be stamped"
ok "ACCEPTED reaches human_acceptance and stamps acceptedAt"

BEFORE="$(jq -r '.reviewAttempt' "$MDIR/review-state.json")"
bash "$STATE" "$MDIR" error CLI_DIED >/dev/null
[ "$(jq -r '.reviewAttempt' "$MDIR/review-state.json")" = "$BEFORE" ] \
  || fail "an execution failure must not spend a review attempt"
[ "$(jq -r '.executionFailures' "$MDIR/review-state.json")" = "1" ] || fail "executionFailures should count"
ok "an execution failure is counted without spending an attempt"

bash "$STATE" "$MDIR" set reviewing >/dev/null
bash "$STATE" "$MDIR" review-start >/dev/null 2>&1 || true
bash "$STATE" "$MDIR" review-start >/dev/null 2>&1 || true
if bash "$STATE" "$MDIR" review-start >/dev/null 2>&1; then
  fail "review-start should refuse past maxReviewAttempts"
fi
[ "$(bash "$STATE" "$MDIR" status)" = "blocked" ] || fail "exhausted attempts should block"
[ "$(jq -r '.blockedReason' "$MDIR/review-state.json")" = "REVIEW_ATTEMPTS_EXHAUSTED" ] \
  || fail "the block reason should be REVIEW_ATTEMPTS_EXHAUSTED"
ok "exhausted review attempts block the Milestone"

printf '== stop-gate.sh\n'

STOP="$PLUGIN_ROOT/hooks/scripts/stop-gate.sh"
FAKE_ROOT="$TMP/repo"
mkdir -p "$FAKE_ROOT/docs/implementation"
cp -R "$MDIR" "$FAKE_ROOT/docs/implementation/M01"
printf 'docs/implementation/M01\n' > "$FAKE_ROOT/.backlog-active"

stop_decision() {
  bash "$PLUGIN_ROOT/scripts/review-state.sh" "$FAKE_ROOT/docs/implementation/M01" set "$1" >/dev/null
  CLAUDE_PROJECT_DIR="$FAKE_ROOT" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$STOP" 2>/dev/null
}

[ -z "$(stop_decision human_acceptance)" ] || fail "human_acceptance should stop"
[ ! -f "$FAKE_ROOT/.backlog-active" ] || fail "stopping should remove .backlog-active"
ok "human_acceptance stops the loop"

printf 'docs/implementation/M01\n' > "$FAKE_ROOT/.backlog-active"
[ -z "$(stop_decision blocked)" ] || fail "blocked should stop"
ok "blocked stops the loop"

for pair in "ready_for_review:/review-milestone" "reviewing:verdict" "fix_required:/fix-milestone" "fixing:fix-done"; do
  st="${pair%%:*}"; want="${pair#*:}"
  printf 'docs/implementation/M01\n' > "$FAKE_ROOT/.backlog-active"
  OUT="$(stop_decision "$st")"
  [ "$(printf '%s' "$OUT" | jq -r '.decision')" = "block" ] || fail "$st should block the stop"
  printf '%s' "$OUT" | jq -r '.reason' | grep -q -- "$want" || fail "$st should mention $want"
  ok "$st blocks and points at $want"
done

printf 'docs/implementation/M01\n' > "$FAKE_ROOT/.backlog-active"
OUT="$(stop_decision implementing)"
[ "$(printf '%s' "$OUT" | jq -r '.decision')" = "block" ] || fail "implementing with work left should block"
ok "implementing keeps the loop going"

rm -f "$FAKE_ROOT/.backlog-active"
[ -z "$(CLAUDE_PROJECT_DIR="$FAKE_ROOT" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$STOP" 2>/dev/null)" ] \
  || fail "the Stop hook must be inert with no .backlog-active"
ok "the Stop hook is inert outside a run"

printf '== task-gate.sh\n'

GATE="$PLUGIN_ROOT/hooks/scripts/task-gate.sh"
printf 'docs/implementation/M01\n' > "$FAKE_ROOT/.backlog-active"
OPEN="$(jq -r '[.stories[]|select(.status=="pending")][0].id' "$FAKE_ROOT/docs/implementation/M01/tasks.json")"

if printf '{"task":{"title":"%s: something"}}' "$OPEN" \
   | CLAUDE_PROJECT_DIR="$FAKE_ROOT" bash "$GATE" >/dev/null 2>&1; then
  fail "closing a task over an open Story should exit 2"
fi
ok "a task over an open Story is refused"

printf '{"task":{"title":"%s: done one"}}' "$FIRST" \
  | CLAUDE_PROJECT_DIR="$FAKE_ROOT" bash "$GATE" >/dev/null 2>&1 \
  || fail "a task over a done Story should pass"
ok "a task over a done Story passes"

printf '{"task":{"title":"no story id here"}}' \
  | CLAUDE_PROJECT_DIR="$FAKE_ROOT" bash "$GATE" >/dev/null 2>&1 \
  || fail "an unrelated task should pass"
ok "an unrelated task is ignored"

printf '== guard-edit.sh\n'

EDIT="$PLUGIN_ROOT/hooks/scripts/guard-edit.sh"
# A guard that allows the call prints nothing at all, so an empty result means
# "allow" — jq has no input to apply a default to.
decision_of() {
  if [ -z "$1" ]; then printf 'allow\n'
  else printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
  fi
}

guard_edit() {
  decision_of "$(printf '{"tool_input":{"file_path":"%s/%s"}}' "$REPO_ROOT" "$1" \
    | CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$EDIT" 2>/dev/null)"
}

[ "$(guard_edit bin/stop-gate)" = "deny" ] || fail "bin/stop-gate must be denied"
ok "editing bin/stop-gate is denied"
[ "$(guard_edit lib/gates/stop_gate.rb)" = "deny" ] || fail "lib/gates must be denied"
ok "editing lib/gates is denied"
[ "$(guard_edit docs/AGENT_RULES.md)" = "deny" ] || fail "AGENT_RULES must be denied"
ok "editing docs/AGENT_RULES.md is denied"
[ "$(guard_edit docs/architecture/01-foundation.md)" = "deny" ] || fail "architecture must be denied"
ok "editing docs/architecture is denied"
[ "$(guard_edit .rubocop.yml)" = "ask" ] || fail ".rubocop.yml should ask"
ok "editing .rubocop.yml asks"
[ "$(guard_edit app/models/service.rb)" = "allow" ] || fail "ordinary code should be allowed"
ok "ordinary application code is allowed"

printf '== guard-bash.sh\n'

BASHG="$PLUGIN_ROOT/hooks/scripts/guard-bash.sh"
guard_bash() {
  decision_of "$(printf '{"tool_input":{"command":"%s"}}' "$1" | bash "$BASHG" 2>/dev/null)"
}

[ "$(guard_bash 'git push --force origin main')" = "deny" ] || fail "force push must be denied"
ok "force push is denied"
[ "$(guard_bash 'bin/rails db:drop')" = "deny" ] || fail "db:drop must be denied"
ok "db:drop is denied"
[ "$(guard_bash 'docker swarm init --force-new-cluster')" = "deny" ] || fail "force-new-cluster must be denied"
ok "force-new-cluster is denied"
[ "$(guard_bash 'terraform apply')" = "ask" ] || fail "terraform should ask"
ok "terraform asks"
[ "$(guard_bash 'git commit --no-verify -m x')" = "ask" ] || fail "--no-verify should ask"
ok "--no-verify asks"
[ "$(guard_bash 'bin/test')" = "allow" ] || fail "ordinary commands should be allowed"
ok "an ordinary command is allowed"

printf '\n%s checks passed\n' "$PASS"
printf 'SMOKE OK\n'
