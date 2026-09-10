#!/usr/bin/env python3
"""Bound reviewer tool use by elapsed time, including within a single turn."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time

payload = json.load(sys.stdin)
root = Path(os.environ.get("CLAUDE_PROJECT_DIR", payload.get("cwd", os.getcwd())))
if not (root / ".backlog-active").is_file():
    sys.exit(0)
agent = payload.get("agent_id")
if not agent:
    sys.exit(0)
key = hashlib.sha256((payload.get("session_id", "") + ":" + agent).encode()).hexdigest()
path = root / "tmp/opanel-loop/review-budgets" / (key + ".json")
event = payload.get("hook_event_name")
if event == "SubagentStart":
    if payload.get("agent_type", "").split(":")[-1] != "reviewer":
        sys.exit(0)
    story = None
    milestone = root / (root / ".backlog-active").read_text().splitlines()[0].strip()
    tasks_file = milestone / "tasks.json"
    if tasks_file.is_file():
        stories = json.loads(tasks_file.read_text()).get("stories", [])
        story = next((s["id"] for s in stories if s.get("status") in
                      ("in_progress", "review", "fix_required")), None)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Repeated start events after compaction must not reset the deadline.
    try:
        with path.open("x") as handle:
            json.dump({"deadline": time.time() + 300, "expired": False, "story": story}, handle)
    except FileExistsError:
        pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event,
        "additionalContext": "Review budget: 300 seconds. Read the diff and recorded evidence; return findings in your final response. Unverified criteria block completion. Do not run gates or mutate files."}}))
elif event == "PreToolUse" and path.exists():
    record = json.loads(path.read_text())
    if time.time() >= record["deadline"]:
        record["expired"] = True
        path.write_text(json.dumps(record))
        print(json.dumps({"continue": False, "stopReason":
            "Review reached its 300-second budget. It is incomplete, not approved. The lead must preserve verified findings and record unverified scope."}))
