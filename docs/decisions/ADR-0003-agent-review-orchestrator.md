---
title: "ADR-0003 — Milestone implementation and review orchestrator"
status: "superseded"
date: "2026-09-06"
superseded-by: "ADR-0004"
---

# ADR-0003 — Milestone implementation and review orchestrator

> **Superseded by [`ADR-0004`](ADR-0004-in-process-milestone-loop.md) on 2026-09-08.**
> The role separation this ADR established still holds — whoever implements does
> not approve. What changed is where the reviewer runs: three dispatches failed
> inside the external CLI without producing a verdict, and the loop is now
> in-process. This document is kept as the record of why the separation exists.

## Context

Milestones are implemented by Claude and independently reviewed by Codex. The
existing Stop hook could start a single Codex review, but it had no durable state,
no correction loop, no attempt limit, and no human gate. Prompt-only role
separation was insufficient because a reviewer could still receive write access.

`M00-14` excludes a productized headless Dev Orchestrator from the Milestone.
This decision instead adds a repository-local engineering harness required before
M00 implementation begins; it is not an Opanel runtime capability and does not
count toward any product Story.

## Decision

Use a small Bash + JSON state machine for the repository workflow:

```text
Claude IMPLEMENTER -> ready_for_review
Codex REVIEWER (read-only) -> accepted | fix_required
Claude IMPLEMENTER (fix) -> ready_for_review
accepted -> human_acceptance
```

Each Milestone opts in with `review-state.json`. Codex runs non-interactively
with a read-only sandbox and structured output. Claude runs non-interactively
only for bounded fixes. Review and fix attempts are capped; non-convergence or
invalid agent output moves the Milestone to `blocked`. No transition starts the
next Milestone.

## Consequences

- Agent roles are enforced both by prompts and runner permissions.
- State survives context loss and every review/fix produces a numbered artifact.
- A failed or malformed agent execution blocks safely instead of looping.
- Human acceptance remains mandatory between Milestones.
- The harness depends on Bash, `jq`, the authenticated `claude` CLI, and the
  authenticated `codex` CLI.

## Alternatives considered

- Prompt-only handoff: rejected because it does not enforce read-only review.
- A one-way Stop hook: rejected because it cannot drive bounded correction loops.
- A service or general workflow platform: rejected as disproportionate to the
  current repository-local need.

## Affected docs

- `.claude/settings.json`
- `docs/goals/REVIEW_MILESTONE.md`
- `docs/goals/FIX_REVIEW_FINDINGS.md`
- `docs/implementation/M00/GOAL.md`
- `docs/implementation/M00/review-state.json`

## Affected modules

- `scripts/agent-orchestrator.sh`
- `scripts/run-codex-review.sh`
- `scripts/run-claude-fix.sh`
