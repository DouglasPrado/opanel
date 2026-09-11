#!/usr/bin/env python3
"""Exercise deadlines and maintenance permissions without running Claude."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

plugin = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / ".backlog-active").write_text("docs/implementation/M01\n")
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))

    def budget(event, agent="review-1", kind="opanel-loop:reviewer"):
        payload = dict(hook_event_name=event, agent_id=agent, agent_type=kind,
                       session_id="test-session", cwd=str(root), tool_name="Read")
        result = subprocess.run(["python3", str(plugin / "hooks/scripts/review-budget.py")],
                                input=json.dumps(payload), text=True, capture_output=True, env=env, check=True)
        return json.loads(result.stdout) if result.stdout else {}

    assert budget("SubagentStart")["hookSpecificOutput"]["hookEventName"] == "SubagentStart"
    path = next((root / "tmp/opanel-loop/review-budgets").glob("*.json"))
    original = json.loads(path.read_text())
    budget("SubagentStart")
    assert json.loads(path.read_text())["deadline"] == original["deadline"]
    assert budget("PreToolUse") == {}
    original["deadline"] = time.time() - 1
    path.write_text(json.dumps(original))
    assert budget("PreToolUse")["continue"] is False
    assert json.loads(path.read_text())["expired"] is True
    assert budget("PreToolUse", agent="builder-1", kind="opanel-loop:builder") == {}

    def guard(path):
        payload = {"tool_input": {"file_path": str(root / path)}}
        result = subprocess.run(["bash", str(plugin / "hooks/scripts/guard-edit.sh")],
                                input=json.dumps(payload), text=True, capture_output=True, env=env, check=True)
        return json.loads(result.stdout) if result.stdout else {}

    assert guard("bin/gate")["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert guard("tools/opanel-loop/agents/reviewer.md")["hookSpecificOutput"]["permissionDecision"] == "deny"
    (root / ".backlog-active").unlink()
    assert budget("PreToolUse") == {}
    assert guard("bin/gate") == {}
    assert guard("docs/architecture/01-foundation.md")["hookSpecificOutput"]["permissionDecision"] == "deny"

    milestone = root / "M01"
    milestone.mkdir()
    (milestone / "tasks.json").write_text(json.dumps({"stories": [{"id": "M01-01", "status": "in_progress", "attempts": 0}]}))
    for attempt in range(1, 4):
        result = subprocess.run(["bash", str(plugin / "scripts/tasks.sh"), str(milestone), "attempt", "M01-01"], capture_output=True, text=True, check=True)
        assert result.stdout.strip() == str(attempt)
    result = subprocess.run(["bash", str(plugin / "scripts/tasks.sh"), str(milestone), "attempt", "M01-01"], capture_output=True, text=True)
    assert result.returncode == 2
    story = json.loads((milestone / "tasks.json").read_text())["stories"][0]
    assert story["status"] == "blocked" and story["attempts"] == 3
print("BUDGET OK: deadline, compaction, scope, maintenance and attempt exhaustion")
