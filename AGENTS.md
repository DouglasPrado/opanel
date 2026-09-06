# AGENTS.md — Opanel

Adapter for Codex and other agents that use this file as the repository entrypoint.

The rules are not here. They are in **[`docs/AGENT_RULES.md`](docs/AGENT_RULES.md)** — canonical and harness-agnostic. This file only tells you how to enter the repository.

## Read first

1. [`docs/AGENT_RULES.md`](docs/AGENT_RULES.md) — engineering rules, architecture invariants, security, testing, gates.
2. [`docs/MASTER.md`](docs/MASTER.md) — map of the specification; use it to find the right document.

## Non-negotiable context

- The product is named **Opanel**. Never write `OpenEL`.
- Stack: **Rails 8.1.x + PostgreSQL + Solid Queue**, interface in **Rails + Inertia + React/TypeScript** (Vite, Tailwind). Not Next.js, not HTMX. Reuse the existing React components.
- Platform: Docker Engine, Docker Swarm, Traefik, Railpack, BuildKit, OCI Registry.
- Changing the stack or the architecture requires an ADR in `docs/decisions/`, never agent preference.

## For every Story

1. Read the Story completely.
2. Read only the documents it references.
3. Inspect the existing implementation before editing.
4. Keep changes inside the Story's declared boundary — smallest complete solution.
5. Run the tests the Story requires and record the results.
6. Self-review the diff against Story, architecture, security and tests.
7. Report conflicts instead of redesigning silently.

For high-impact changes — schema, security, authorization, reconciliation, Operations, public contracts, risky migrations — produce a plan and get it reviewed before editing.

## Hard limits

- Applications run as Docker Swarm Services; only the Swarm Executor touches `/var/run/docker.sock`.
- PostgreSQL is Desired State; Docker Swarm is Actual State; reconcilers converge and never rewrite user intent.
- MCP goes through the Application Layer, never straight to Docker.
- Secrets never appear in logs, exceptions, responses, event payloads or audit records.
- Never delete a test, weaken an assertion, disable a lint or security rule, lower a threshold, or change an acceptance criterion to get a green build. Fix the implementation.
- Never touch real production infrastructure autonomously: production deploy, destructive database operations, cluster deletion, `force-new-cluster`, production restore, recovery-key rotation, production secret deletion, production DNS or certificate changes. These need an explicit human gate.

## Report at the end of a Story

Files changed · decisions taken · schema/API/event changes · tests executed with results · acceptance criteria satisfied · new dependencies with justification · open conflicts or blockers.

## Context recovery

`AGENTS.md` → `docs/MASTER.md` → `docs/AGENT_RULES.md` → current milestone in `docs/implementation/` → its `tasks.json` → current Story → `git log` / `git status`.

Git and the Implementation Pack are the source of truth. Do not reconstruct the architecture from memory.
