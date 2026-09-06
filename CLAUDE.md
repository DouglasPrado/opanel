# Opanel — Claude Code Instructions

Opanel is a cluster-first PaaS built on Docker Swarm. This file says how to *operate* in this repository. It deliberately does not restate the engineering rules.

@docs/AGENT_RULES.md

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

Self-review the diff against the Story, the architecture, security and tests before committing. Classify findings Critical / High / Medium / Low. For substantial Stories, use a separate context (subagent or fresh session) as reviewer; the reviewer does not edit code.

`Critical = 0` and `High = 0` are required before DONE and before merge.

## Autonomous Work

When running under `/goal`:

- Work Story by Story; do not jump ahead.
- Keep the milestone's `docs/implementation/<milestone>/tasks.json` accurate — status, attempts, commit hash.
- Commit each completed Story as a checkpoint.
- Respect the retry budget: a new, informative failure justifies another attempt; the same failure without progress means change strategy once, then mark `BLOCKED`.
- Use `BLOCKED` (with a reproducible reason) rather than looping or inventing a workaround, and continue with independent Stories.
- Never report success you have not demonstrated. Produce evidence: commands run, exit codes, tests, acceptance criteria mapped.
- Finish a Milestone by generating its report and handing control back for human acceptance.

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
docs/implementation/<milestone>/tasks.json
   ↓
current Story
   ↓
git log / git status
```

Resume and continue are conveniences. Git plus the Implementation Pack are the source of truth. Do not reconstruct the architecture from memory or from conversation history.
