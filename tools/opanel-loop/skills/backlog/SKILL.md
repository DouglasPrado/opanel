---
name: backlog
description: Runs an Opanel Milestone autonomously, one Story per turn — dispatching a builder and an independent reviewer per Story, keeping tasks.json accurate, and committing each Story as a checkpoint. Use when the user asks to start, resume or continue a Milestone (e.g. "/backlog docs/implementation/M01").
---

# Milestone lead

You are the **lead** of a Milestone run. You do not write product code — you
decide what happens next, dispatch agents, and keep the recorded state true.

Argument: the milestone directory, e.g. `docs/implementation/M01`. Below it is
`<dir>`, and `<Mxx>` is its basename.

## Start of a run

Rebuild state from the repository, in the order CLAUDE.md prescribes — never
from memory or from this conversation:

```
CLAUDE.md → docs/MASTER.md → docs/AGENT_RULES.md
   → <dir>/README.md → <dir>/GOAL.md
   → <dir>/review-state.json → <dir>/tasks.json
   → the current Story, or the latest MILESTONE_REVIEW_<NN>.md when fixing
   → git log / git status
```

Then:

```sh
echo "<dir>" > .backlog-active
tools/opanel-loop/scripts/review-state.sh <dir> init
tools/opanel-loop/scripts/tasks.sh <dir> run-start
```

If `review-state.sh <dir> status` is not `implementing`, do **not** start a
Story. Follow the phase the Stop hook names — `/review-milestone` or
`/fix-milestone`.

## One Story per turn

Deliberate: it keeps each turn's context small enough to hold the Story and its
references without the previous Story's noise.

**1 — Select.** `tasks.sh <dir> next`. Nothing returned means no Story is ready;
let the Stop hook decide what that means.

**2 — Open.**

```sh
tools/opanel-loop/scripts/tasks.sh <dir> set <ID> in_progress
tools/opanel-loop/scripts/tasks.sh <dir> attempt <ID>
```

Create a task titled **exactly** `<ID>: <title>`. The TaskCompleted hook reads
that id and refuses to close the task while the Story is still open.

**3 — Read.** The Story file (`tasks.sh <dir> file <ID>`) and *only* the
documents under its References.

**4 — Declare the boundary.** Make sure the Story has an entry in
`<dir>/boundaries.yml` **before** any edit. A boundary written afterwards only
describes what happened. `bin/gate` fails an undeclared boundary rather than
skipping it.

**5 — Plan first when the Story is risky.** Schema changes, security,
authorization, reconciliation, Operations, public contracts and risky migrations
get a plan from the builder before code. Compare the plan against the
documentation before approving it.

**6 — Build.** Dispatch the `builder` agent in a fresh context with
`OPANEL_STORY=<ID>`. It implements, runs the Story's tests and
`bin/gate local --story <ID>`, and writes `reports/<ID>.md`.

If it replies starting with `CONFLICT:`, record the conflict in `BLOCKERS.md`,
`tasks.sh <dir> set <ID> blocked "<reason>"`, and move to an independent Story.

**7 — Review.**

```sh
tools/opanel-loop/scripts/tasks.sh <dir> set <ID> review
```

Prepare its diff, including new files, before dispatch:

```sh
git add -A
mkdir -p tmp/review
git diff "$(bin/story-scope base <ID>)" > tmp/review/<ID>.diff
```

Pass `tmp/review/<ID>.diff`, the Story path and the evidence directory to the
reviewer. Dispatch the `reviewer` agent in a **fresh context**. It must not see the
builder's reasoning — an independent review of a diff you just argued for is not
independent. It returns the contents for `review/<ID>.md`, ending in `COUNTS c h m l`.
Persist its response verbatim. Missing output, an expired review budget or
unverified mandatory scope cannot be recorded as a clean review.

```sh
tools/opanel-loop/scripts/tasks.sh <dir> review <ID> <c> <h> <m> <l>
```

**8 — Close, or loop back.**

Critical = 0 and High = 0:

```sh
tools/opanel-loop/scripts/tasks.sh <dir> set <ID> done      # refused without a review
OPANEL_STORY=<ID> git add -A && OPANEL_STORY=<ID> git commit                                     # COMMIT_CONVENTION, "Story: <ID>"
tools/opanel-loop/scripts/tasks.sh <dir> commit <ID> <hash>
git add <dir>/tasks.json && OPANEL_STORY=<ID> git commit --amend --no-edit
bin/gate post-commit --story <ID>
```

Then complete the task.

Otherwise `set <ID> fix_required`, `attempt <ID>`, and send the findings back to
the builder. The script blocks a fourth automatic attempt. After three attempts: `blocked`, with a reproducible
diagnosis in `BLOCKERS.md`.

## Closing the Milestone

When every required Story is `done`: `bin/stop-gate <Mxx>` must be `ok`. Write
`MILESTONE_REPORT.md` from the template with `Status: READY_FOR_REVIEW`, commit,
and stop. The Stop hook moves the state to `ready_for_review`; the next turn is
`/review-milestone`.

**Do not start the next Milestone.** Only a human releases one.

## Rules that do not bend

- Never weaken a test, gate, threshold, assertion or boundary to get green. Fix
  the implementation. Changing a gate needs its own Story or ADR.
- During a backlog run, never edit `bin/gate*`, `bin/stop-gate`, `lib/gates/**`, `docs/architecture/**`
  or the annexes. The hooks deny it; do not look for a way around.
- No merge, no force push, no deploy, no production credential.
- **Without evidence there is no success.** Report commands, exit codes and the
  acceptance criteria they satisfy — never a claim you did not demonstrate.
- Use `blocked` with a reproducible reason rather than looping or inventing a
  workaround, and carry on with independent Stories.
