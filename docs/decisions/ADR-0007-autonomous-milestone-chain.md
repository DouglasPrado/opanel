# ADR-0007 — Autonomous milestone chain, arbitration instead of human gates

Date: 2026-09-10
Status: accepted on the owner's explicit instruction

## Problem

The loop stops for a human at eight distinct points, and in an unattended run
every one of them ends the run rather than pausing it:

| Stop | Where |
|---|---|
| `human_acceptance` after an ACCEPTED milestone verdict | `review-state.sh:143`, `stop-gate.sh` |
| `blocked` for any reason | `stop-gate.sh` |
| a required Story blocked | `REQUIRED_STORY_BLOCKED` |
| review or fix attempts exhausted | `cmd_review_start`, `cmd_fix_start` |
| the fourth Story attempt | `tasks.sh` |
| a specification conflict needing a product decision | `SPEC_CONFLICTS.md` |
| an `ask` decision from `guard-bash.sh` with nobody to answer | hooks |
| a red `bin/stop-gate` with no path forward | `stop-gate.sh` |

Measured cost of this design on M01: Stories of *product* converged in 1.8–2.7 h
each, but the run has produced no product Story since 2026-09-10 02:39. Three
Stories about the loop's own machinery (`M01-91`, `M01-92`, `M01-93`) consumed
six, two and three attempts; `M01-92` is blocked because `guard-edit.sh` denies
the implementer the very files its acceptance criteria require. 197 Stories
across 14 Milestones remain behind those stops.

There is no milestone chaining at all: `/backlog` runs one Milestone and the
Stop hook ends the run. Every subsequent Milestone needs a human to launch it.

## Decision

The owner has decided the pipeline runs unattended end to end. Four changes.

**1 — An arbiter agent replaces the human at every decision point above.**
`tools/opanel-loop/agents/arbiter.md` runs in a fresh context, read-mostly, and
returns one of three verdicts for each situation it is handed: `FIX` (one bounded
round), `DEBT` (record and proceed) or `BLOCK` (reserved for what no decision can
resolve). Its authority and its limits are listed in the agent file. Every
decision is appended to `<dir>/DECISIONS.md` with the situation, the evidence it
read, the verdict and the reason — an append-only ledger, so an unattended run is
auditable after the fact rather than opaque.

**2 — A gate result routes to the arbiter instead of halting the run.**
This specialises Annex I §21.2 for autonomous execution. No gate, scanner rule,
assertion or threshold is removed, weakened or made optional: every check still
runs and still records its result. What changes is only what a red result *does* —
it opens an arbitration instead of ending the run. `Critical = 0` and `High = 0`
remain required for a Story to be `done`; a finding the arbiter rules `DEBT` is
not silently downgraded, it is carried out of the Story into the Milestone's debt
ledger and reproduced verbatim in the Pull Request body.

**3 — `human_acceptance` becomes `accepted`, and releases the next Milestone.**
An ACCEPTED verdict lands on `accepted` through `review-state.sh arbitrate`,
which requires an arbiter decision recorded in `DECISIONS.md` and refuses to run
without one. The autopilot then opens the Milestone's Pull Request and starts the
next eligible Milestone from `docs/implementation/DEPENDENCIES.md`.

**4 — Milestone branches and Pull Requests are stacked.**
`milestone/m<NN>` branches from the previous Milestone's branch, and its Pull
Request targets that branch, not `main`. Each PR therefore shows only its own
Milestone's diff. Nothing merges to `main` autonomously: the stack of open PRs is
where the human enters, and it is the only place a human is still required.

## What does not change

- The implementer never reviews its own work. Builder, reviewer,
  milestone-reviewer and arbiter are separate agents in separate contexts.
- `guard-bash.sh`'s **deny** list is untouched. Production deploys, destructive
  database operations, `force-new-cluster`, force pushes and production
  credentials stay refused, and the arbiter may not overrule them. Only the
  **ask** list becomes an arbiter decision.
- `guard-edit.sh` keeps denying the running loop its own gates and plugin. The
  fix for `M01-92` is not to relax the guard; it is that gate maintenance is not
  a Milestone Story. Those Stories leave `tasks.json`.
- No merge to `main`, no deploy, no production credential, in any branch of the
  autopilot.

## Consequences

A defect accepted as `DEBT` in an early Milestone propagates into the Milestones
stacked on top of it, and is discovered later and more expensively than a human
gate would have caught it. This is the cost the owner has accepted in exchange for
throughput. Two things bound it: `Critical` findings still block a Story, and the
debt ledger travels into every PR body, so the stack is reviewable in the order it
was built.

`maxReviewAttempts` and `maxFixAttempts` still exist. Exhausting them is now an
arbitration rather than a stop, and the arbiter may raise a budget once per
Milestone through `review-state.sh budget`, with its reason recorded.
