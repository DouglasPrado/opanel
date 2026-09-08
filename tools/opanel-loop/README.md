# opanel-loop

Runs an Opanel Milestone autonomously inside Claude Code: one Story per turn, an
independent reviewer in a fresh context, and Stop Gates that decide when the loop
may stop.

It replaces the external orchestrator (`scripts/agent-orchestrator.sh`,
`run-codex-review.sh`, `run-claude-fix.sh`, now in `scripts/legacy/`). Same
separation of roles, no second CLI in the critical path.

## Install

```jsonc
// .claude/settings.json
{ "plugins": ["./tools/opanel-loop"] }
```

Requires `jq`. Uses `flock` when available and falls back to an atomic `mkdir`
lock otherwise, so it works on macOS.

## Use

```sh
/backlog docs/implementation/M01           # run the Milestone
/review-milestone docs/implementation/M01  # independent review
/fix-milestone docs/implementation/M01     # correct the blocking findings
```

`/backlog` writes `.backlog-active` at the repository root. Every hook here is
inert without that file, so ordinary sessions are unaffected. Removing it stops
the loop.

## How it works

```
implementing ──> ready_for_review ──> reviewing ──┬─> human_acceptance   (human)
     ^                                            │
     └──── fixing <── fix_required <──────────────┘
```

The Stop hook reads the recorded state each turn and either blocks the stop with
the next concrete action or lets the loop end. The agent never decides that its
own work is finished — `bin/stop-gate` does.

Per Story: `builder` implements, then `reviewer` judges it in a fresh context
that never saw the builder's reasoning. `done` is refused unless the review
exists and records Critical = 0 and High = 0.

## Layout

```
.claude-plugin/plugin.json
skills/{backlog,review-milestone,fix-milestone}/SKILL.md
agents/{builder,reviewer,milestone-reviewer}.md
hooks/hooks.json
hooks/scripts/{session-start,guard-bash,guard-edit,post-edit,task-gate,stop-gate}.sh
scripts/{tasks.sh,review-state.sh,smoke-test.sh,_lib.sh}
```

`tasks.sh` and `review-state.sh` are the only writers of `tasks.json` and
`review-state.json`. Both refuse the transitions that would let an implementer
approve its own work.

## Tests

```sh
tools/opanel-loop/scripts/smoke-test.sh   # 46 checks, prints SMOKE OK
```

It runs against a throwaway copy of a real milestone and covers the refusals —
`done` without a review, `ACCEPTED` with findings, a task closed over an open
Story, an edit to `bin/stop-gate`. A gate proved only on its happy path is not
proved at all.

## Escape hatches

- `OPANEL_MAX_STORIES_PER_RUN` — stop cleanly after N Stories (checkpointing).
- Delete `.backlog-active` to stop the loop after the current turn.
- Turn budget: `stories × 6 + 30`. Reaching it blocks the Milestone.
