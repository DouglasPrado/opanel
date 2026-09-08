# Opanel — Claude Code Instructions

Opanel is a cluster-first PaaS built on Docker Swarm. This file says how to *operate* in this repository. It deliberately does not restate the engineering rules.

@docs/AGENT_RULES.md

## Fixed Role — IMPLEMENTER

Claude is the **IMPLEMENTER**. Claude implements Stories and, when the loop
requests it, fixes blocking findings from an independent review.

**The implementer never approves its own work.** Per [`ADR-0004`](docs/decisions/ADR-0004-in-process-milestone-loop.md),
the independent Milestone review is a Claude subagent — read-only, in a fresh
context that never saw the implementer's reasoning, on a different model. That is
a role, not a mood: the session implementing a Milestone must not review it.

While acting as the implementer, Claude must not:

- write a review artifact — `MILESTONE_REVIEW_<NN>.md`, or the legacy
  `CODEX_REVIEW_<NN>.md` — by hand;
- emit `ACCEPTED` or `NOT_ACCEPTED` as a verdict, or correct the reviewer's
  counts. Correcting a verdict is writing it;
- set `review-state.json` outside the scripts. `tools/opanel-loop/scripts/review-state.sh`
  owns those transitions and refuses `ACCEPTED` with any blocking finding;
- declare `human_acceptance`, or start the next Milestone. Only a human does;
- substitute the independent review with its own self-review;
- modify the loop — its scripts, schemas, hooks, agents or skills — while
  executing a Milestone or fixing review findings. Outside a run, and on human
  instruction, that change is ordinary work and belongs in its own commit.

Claude requests review by finishing implementation or fixes and letting
`review-state.sh` reach `ready_for_review`. The Stop hook then decides what
happens next; see [`docs/implementation/AGENT_ORCHESTRATOR.md`](docs/implementation/AGENT_ORCHESTRATOR.md).

## Start Here

- The product is named **Opanel**. Never write `OpenEL`.
- The Control Plane is **Rails 8.1.x + PostgreSQL + Solid Queue**, with a **Rails + Inertia + React/TypeScript** interface (Vite, Tailwind). Not Next.js. Not HTMX. Reuse the existing React components.
- The unit of work is a **Story**, not "the platform". Anything larger needs a Story first.
- Never change the approved stack or architecture by preference. That requires an ADR in `docs/decisions/`.

## Source of Truth

| Need | Read |
|---|---|
| Which document decides this? | `docs/MASTER.md` |
| How must this be built? | `docs/AGENT_RULES.md` (canonical, harness-agnostic) |
| What am I building now? | the current Story in `docs/implementation/` |
| Process, gates, review | `docs/annexes/I-engineering-playbook-quality-gates.md` |
| Agent process, Story templates | `docs/annexes/G-agent-oriented-development.md` |
| Autonomous loop | `docs/annexes/H-autonomous-development-loop.md` |
| Security | `docs/annexes/C-threat-model-security-hardening.md` |
| Testing | `docs/annexes/D-test-strategy.md` |
| Known doc/decision divergences | `docs/decisions/pending-documentation-updates.md` |

Precedence: approved architecture → current Story → Engineering Playbook → `docs/AGENT_RULES.md` → this file → your preference.

## Mandatory Workflow

Before substantial work:

1. Read `docs/MASTER.md`.
2. Read `docs/AGENT_RULES.md`.
3. Read the current Story completely.
4. Read only the specification documents that Story references.
5. Inspect the existing implementation before proposing changes.

Then: plan (when the change is substantial) → implement → run the Story's tests → self-review the diff → gates → commit → report.

## Scope Discipline

Implement the **smallest complete solution** that satisfies Story + architecture + quality gates.

Do not implement future Stories, refactor adjacent modules without need, add speculative abstractions or extension points, add dependencies without justification, or widen the diff beyond the Story's boundary. Strategic refactors get their own Story.

If the Story and approved documentation conflict, do not choose silently: record the conflict, explain the impact, stop only the affected part, and keep working on everything unaffected. See "Specification Conflicts" in `docs/AGENT_RULES.md`.

## Planning

Use plan mode before editing for schema changes, security, authorization, reconciliation, Operations, public contracts and risky migrations.

A plan covers: schema, domain, authorization, jobs, operations/reconcilers, tests, security, observability — plus the files you intend to create or change, and any conflict you found against the specification. Compare the plan to the documentation before writing code.

## Implementation

Follow `docs/AGENT_RULES.md`. The invariants that most often get broken by accident:

- Applications run as Swarm **Services**, never raw containers.
- PostgreSQL holds Desired State; Docker Swarm holds Actual State; reconcilers converge one toward the other and never rewrite user intent.
- Only the Swarm Executor touches `/var/run/docker.sock`.
- MCP goes `Agent → MCP → Application Layer → Command/Query → Operation → Reconciler → Executor`. Never `MCP → Docker`.
- Desired State + Operation + Outbox event commit in one transaction; no network call inside a transaction.
- Secrets never reach logs, exceptions, responses, event payloads or audit records.
- UI and public API share the same Application Layer — do not build a REST endpoint just to serve the UI when Inertia covers it.
- Search for an existing React component before creating a new one.

## Testing

Run the suites the Story declares, before claiming completion, and surface the commands and results in the transcript.

Never make a test pass by deleting it, weakening an assertion, disabling a lint or security rule, excluding a file from a scanner, lowering a threshold or editing an acceptance criterion. Fix the implementation. You may not modify a gate or checker to get green — that needs its own Story or ADR.

## Review

Self-review the diff against the Story, the architecture, security and tests before committing. This is an implementation quality check, not the independent Milestone review. Do not create a Codex verdict and do not use a Claude subagent or fresh Claude session to replace Codex.

`Critical = 0` and `High = 0` are required before DONE and before merge.

## Autonomous Work

When running under `/goal`:

- Work Story by Story; do not jump ahead.
- Keep the milestone's `docs/implementation/<milestone>/tasks.json` accurate — status, attempts, commit hash.
- Read `docs/implementation/<milestone>/review-state.json` before acting. Work on
  the original Goal only in `implementing`; work from the latest Codex review
  only in `fixing`.
- Commit each completed Story as a checkpoint.
- Respect the retry budget: a new, informative failure justifies another attempt; the same failure without progress means change strategy once, then mark `BLOCKED`.
- Use `BLOCKED` (with a reproducible reason) rather than looping or inventing a workaround, and continue with independent Stories.
- Never report success you have not demonstrated. Produce evidence: commands run, exit codes, tests, acceptance criteria mapped.
- Finish initial implementation by generating `MILESTONE_REPORT.md` with
  `Status: READY_FOR_REVIEW`, setting `review-state.json.status` to
  `ready_for_review`, and stopping. Do not start the next Milestone.
- In `fixing`, read the latest `CODEX_REVIEW_<NN>.md`, follow
  `docs/goals/FIX_REVIEW_FINDINGS.md`, correct only blocking findings, generate
  `FIX_REPORT_<NN>.md`, run the required tests and gates, set
  `review-state.json.status` to `ready_for_review`, and stop.
- Never declare human acceptance. Only the orchestrator may move an accepted
  Codex verdict to `human_acceptance`, and only a human may release the next
  Milestone.

Do not finish a Story until: implementation complete, tests green, quality gates green, self-review complete, acceptance criteria satisfied.

## Dangerous Actions

Never perform these autonomously against real infrastructure. Each requires an explicit human gate:

```text
production deploy
destructive database operation
delete cluster
force-new-cluster
restore production
rotate recovery key
delete production secrets
modify production DNS
modify production certificates
```

Also out of bounds: force-push to a protected branch, editing architecture documents to make a test pass, disabling tests or gates to complete a goal, and any use of production credentials. No production credential should exist in the workspace at all.

## Context Recovery

If context is lost or a new session starts, rebuild state from the repository — never from memory:

```text
CLAUDE.md
   ↓
docs/MASTER.md
   ↓
docs/AGENT_RULES.md
   ↓
current milestone in docs/implementation/
   ↓
docs/implementation/<milestone>/review-state.json
   ↓
docs/implementation/<milestone>/tasks.json
   ↓
current Story or latest CODEX_REVIEW_<NN>.md when status is fixing
   ↓
git log / git status
```

Resume and continue are conveniences. Git plus the Implementation Pack are the source of truth. Do not reconstruct the architecture from memory or from conversation history.
