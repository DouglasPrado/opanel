---
title: "Opanel Agent Engineering Rules"
type: "rules"
status: "approved"
---

# Opanel Agent Engineering Rules

Canonical, harness-agnostic engineering rules for any coding agent working on Opanel.

`docs/MASTER.md` is the **map** of the specification. This file is the **normative rule set** that governs how that specification becomes code. Harness entrypoints (`CLAUDE.md`, `AGENTS.md`) adapt operation to a specific tool and must never contradict this file.

The product is named **Opanel**. Never write `OpenEL`.

## Source of Truth

### Precedence

1. **Approved architecture** — `docs/architecture/01..10` and the normative annexes `docs/annexes/A..I`.
2. **Current Story** — the Implementation Pack file being executed, plus accepted ADRs in `docs/decisions/`.
3. **Engineering Playbook** — `docs/annexes/I-engineering-playbook-quality-gates.md`.
4. **This file** — `docs/AGENT_RULES.md`.
5. **Harness instructions** — `CLAUDE.md`, `AGENTS.md`, and their subtree variants.
6. **Agent preference** — only when no level above decides the matter.

A lower level may *specialize* a higher level. It may never contradict it. This ordering is the same as Annex I §1.2.

If approved documentation and the current Story conflict, **do not decide silently**. Apply the "Specification Conflicts" procedure below: stop only the affected part of the work and continue with everything that is unaffected.

### Reading order before substantial work

1. `docs/MASTER.md` — to locate the right document.
2. This file.
3. The current Story, completely.
4. Only the specification documents the Story references. Do not load the whole corpus into context.
5. The existing implementation in the repository, before proposing or making changes.

### Approved stack

None of this may be substituted by agent preference. A change at this level requires an ADR in `docs/decisions/`.

| Layer | Approved |
|---|---|
| Backend | Ruby on Rails 8.1.x |
| Database | PostgreSQL |
| Jobs / queue | Solid Queue |
| Frontend | React + TypeScript over Inertia.js, bundled with Vite, styled with Tailwind |
| Cluster runtime | Docker Engine + Docker Swarm |
| Ingress | Traefik |
| Build | Railpack + BuildKit |
| Artifacts | OCI Registry |

The Control Plane interface is **Rails + Inertia + React**. It is not a separate Next.js application and it is not HTMX. The existing React components are assets to reuse, not legacy to replace.

## Architecture Invariants

These hold for every Story. Breaking one is a Critical finding, never a local implementation decision.

**Cluster-first.** Platform workloads run as Docker Swarm **Services**. Do not create raw containers for normal platform workloads.

**Desired State lives in PostgreSQL.** It is the configuration the user approved.

**Actual State lives in Docker Swarm.** It is observed, never assumed from the database.

**Reconciliation converges Actual toward Desired:**

```text
Desired State (PostgreSQL)
        ↓
     Reconciler
        ↓
Actual State (Docker Swarm)
```

A reconciler must never promote Actual State into the source of truth, and must never rewrite the user's intent.

**The Docker socket is isolated.** The public API, the web UI, ordinary workers and builders never touch `/var/run/docker.sock`. Only the **Swarm Executor** — manager-only, no public route, typed allowlisted operations — holds that privilege. There is no `exec(command: string)` primitive in the executor.

**MCP never shortcuts the application layer.** Forbidden:

```text
Agent → MCP → Docker
```

Required:

```text
Agent → MCP → Application Layer → Command / Query → Operation → Reconciler → Executor
```

**Secrets stay opaque.** They must not appear in logs, exceptions, serialized responses, event payloads, Operation payloads or audit records. They are versioned (`SecretVersion` is immutable) and distributed under least privilege.

**Infrastructure mutation is asynchronous and durable.** An HTTP request records intent (Desired State + Operation, in one transaction, with an Outbox event). Workers execute. Reconcilers confirm reality. Never hold an HTTP request open while a deploy, scale, drain or certificate operation runs.

**Releases are immutable and identified by digest.** Deploy and rollback work on an OCI `sha256:` digest, never on a mutable tag. Promotion moves an existing artifact between environments; it does not rebuild.

## Scope Discipline

Implement the **smallest complete solution** that satisfies:

```text
Story  +  Architecture  +  Quality Gates
```

Do not:

- implement future Stories early;
- refactor adjacent modules without need;
- add speculative abstractions;
- create hypothetical extension points;
- add dependencies without justification;
- replace an approved technology;
- redesign the architecture silently;
- widen the diff beyond the Story's declared boundary.

If a Story's boundary is unclear, resolve it before editing, not after. Changes outside the declared boundary are a review finding even when the code is correct.

## Engineering Principles

| Principle | In practice |
|---|---|
| Explicitness over magic | Critical flows are visible in Commands, Policies, Jobs, Operations and Reconcilers — not hidden in callbacks. |
| Smallest complete solution | The minimum design that fully satisfies the Story. |
| Server-enforced invariants | Authorization, uniqueness and integrity never depend on the UI. |
| Idempotency by design | Re-executable operations converge without duplicating effects. |
| Desired State is authoritative | Reconcilers converge Actual State; Docker never becomes the primary source of configuration. |
| Observability is part of the feature | A relevant operation ships with the logs, metrics and audit needed to operate it. |
| Secure by default | Missing configuration must not open access, expose a secret or grant privilege. |
| Reuse before creation | Search, compose or extend what exists before creating something new. |
| Reversible change | Prefer rollback-friendly code, schema and rollout (expand-contract). |
| Evidence over confidence | DONE depends on executed checks, not on "looks correct". |

### Anti-overengineering

Do not create, without a concrete present reason:

```text
generic repositories
factories with a single strategy
interfaces with a single implementation
unnecessary internal event buses
generic service layers
wrappers with no real responsibility
speculative plugin systems
abstractions with a single caller
```

An abstraction is justified by real pressure from the Story or by two concrete implementations that need the same contract — never by "it might be useful later". Small duplication is preferable to a wrong abstraction; extract only when the abstraction has a clear name and responsibility.

## Backend Rules

Boundaries (Annex I §4.1). Each type has one job.

### Controllers

Controllers authenticate the context, receive input, validate its shape, call the Application Layer, and render the result — including Inertia responses.

Controllers must not carry significant business logic, talk to Docker, or scatter ad-hoc SQL.

### Models

Active Record represents persistence, relationships, appropriate validations and local invariants.

Callbacks are for local, deterministic behaviour with no external effect. **Never** use a callback to trigger a deploy, a Docker call, DNS, certificates, webhooks, Operation creation, or any critical/external process. Those belong in an explicit Command with a retry and audit path.

### Commands

A relevant mutation gets an explicit Command when that improves atomicity, authorization, auditability, idempotency or clarity. A trivial setter with no rule does not need one.

### Queries

Complex reads may use Query Objects and read models. Do not create a Query Object for a trivial query with no benefit.

### Policies

Authorization is server-side, contextual, and evaluated with Team / Project / Environment explicitly loaded. Never trust the UI for enforcement. Every new mutation or resource scope needs an authorization test, including a cross-team negative test.

### Jobs

Jobs are retry-safe, observable, and idempotent wherever the effect is repeatable. A Job hands off to the Application Layer; it does not duplicate the Command's business rules.

### Reconcilers

```text
read Desired State
read Actual State
calculate diff
apply the smallest safe operation
persist the observation
```

A reconciler acquires a lease with a fencing token, re-inspects the runtime after acting, and never assumes the previous call determined the final state. It must not arbitrarily change Desired State. Diff classes are `NOOP`, `CREATE`, `UPDATE_SAFE`, `ROLLOUT`, `DELETE`, `BLOCKED`, `DRIFT`; for managed resources the default drift policy is Platform Wins, and adoption of runtime state is an explicit admin operation.

### Provider adapters and the Swarm Executor

Provider adapters isolate external APIs and normalize their errors; they do not leak a vendor SDK into the domain. The Swarm Executor is the only privileged Docker boundary and exposes typed operations only.

## Frontend Rules

The interface is Rails + Inertia + React/TypeScript. Preserve and reuse the existing React components.

Conceptual structure — the exact path may vary, but these categories must stay visible (Annex I §6.1):

```text
ui/        # primitives: Button, Input, Dialog, Tabs, ...
shared/    # composed components reused by several features
features/  # components belonging to one domain
layouts/   # shells, navigation, page layouts
pages/     # Inertia pages / entry points
```

- Prefer server-driven props and local UI state.
- Do not introduce a global store for state that belongs to one page or feature.
- Keep remote Control Plane state separate from purely visual state.
- Realtime updates refresh read models/props predictably; the browser never becomes a second source of truth.
- Never import server-only code (database, Docker, infrastructure) into the React tree.
- E2E selectors use roles, semantic attributes or stable test IDs — never fragile CSS classes.

### Inertia and the public API

The UI uses Inertia. Do not build a REST API only to serve the UI when Inertia resolves it naturally.

The public API continues to exist for:

```text
MCP
CLI
integrations
external automation
```

UI and API must reuse the **same Application Layer**. Business rules live in Commands, Queries and Policies, never duplicated per delivery channel.

## Component Reuse

Before creating a new component:

```text
1. search for an existing component (by name, responsibility, appearance, usage)
2. try composition over existing primitives
3. try a small, tested variant or prop
4. only then create a new component
```

**Reuse Gate** (Annex I §6.3):

| Question | If yes | If no |
|---|---|---|
| Does an equivalent component exist? | Reuse it; do not duplicate. | Continue. |
| Does a primitive or composition solve it? | Compose. | Continue. |
| Does a small variant keep it cohesive? | Add a tested variant. | Create a feature-specific component. |
| Is it used by 2+ features? | Consider moving it to `shared/`. | Keep it in the feature. |
| Does the new component replicate an existing visual? | Blocked in review until the difference is justified. | Acceptable. |

The same discipline applies outside the UI: before a new client, retry helper, error envelope or state machine, check whether an existing adapter, policy or lifecycle already covers it. Reuse requires compatible semantics, not merely similar code.

## Database Rules

- Critical integrity lives in PostgreSQL: foreign keys, `NOT NULL`, `CHECK` and `UNIQUE` where appropriate.
- Unique constraints belong in the database, including partial uniques (one active OWNER per Team, slug unique among non-deleted rows, `UNIQUE(secretId, versionNumber)`, `UNIQUE(scope, idempotencyKey)`).
- Every frequent operational query needs a known, verifiable index strategy.
- Ownership and authorization constraints never exist only in the frontend.
- JSONB is for controlled metadata and extensibility — never a substitute for critical relational modelling.
- Migrations follow **expand-contract**; a destructive `DROP`/rename happens only in the contract phase, after the code that depended on the old column is gone.
- Every migration must be backward compatible during rollout, or carry an explicitly approved maintenance window, and must document rollback or forward-fix.
- Avoid N+1 and unbounded collection loads in interactive requests; pagination is mandatory for potentially large collections.
- Use explicit transactions for critical invariants, and locking / leases / unique constraints where real concurrency demands it.
- Network calls (Docker, Git, DNS, Registry, ACME, load balancer) never happen inside a PostgreSQL transaction.

## Async Operations

Every infrastructure mutation is a durable `Operation`, not a synchronous side effect.

- Desired State change + `Operation` + `OutboxEvent` are written in **one transaction**. Publishing to the queue happens afterwards.
- The queue is a delivery mechanism. PostgreSQL remains the source of truth about the Operation; a periodic sweep recovers Operations left without a valid lease.
- Repeatable endpoints accept an `Idempotency-Key`; the same key in the same scope produces one logical operation.
- Retry policy is explicit per operation class. After an unknown outcome, **observe Actual State before repeating** — never blindly retry a non-idempotent effect.
- Resource mutations are serialized per resource (one active operation per `serviceId` / `nodeId`, exclusive lock for cluster-wide work) with TTL leases and fencing tokens.
- A newer revision supersedes an older queued one (`SUPERSEDED`) rather than applying stale configuration.
- Operation payloads carry `SecretVersion` IDs, never plaintext, and are versioned by `schemaVersion`.

## Reconciliation

- Correctness comes from re-reading state, not from trusting an uninterrupted event stream. Docker Events are an accelerator; periodic sweeps are the guarantee.
- Every reconcile run is small, deterministic and resumable, and holds no state in process memory.
- Resources created by Opanel carry ownership labels so they can be identified after a full Control Plane restart. Resources without platform ownership are never adopted or deleted automatically.
- `desiredRevision` / `appliedRevision` track convergence. A resource is only healthy when the applied revision matches the desired revision and the health policy is satisfied.
- Status shown in the UI is **derived**, never a manually stored boolean.

## Security

Non-negotiable, from Annex C:

```text
never log secrets
never expose credentials
never bypass Policies
never expose docker.sock
validate untrusted input
protect SSRF-sensitive operations
verify webhook authenticity
audit privileged operations
```

In detail:

- **Secrets.** Ciphertext only at rest; envelope encryption; `SecretVersion` immutable; reveal is a separate, permissioned, re-authenticated and audited action; redaction applies at every log, error, analytics and audit boundary. The Recovery Key is never persisted recoverably and never appears in logs or backups of the primary store.
- **Authorization.** Deny by default. Never fetch a resource by ID and then trust the route for tenancy — scope the query or validate the owner chain. Opaque IDs reduce enumeration but do not replace authorization.
- **Docker.** No component other than the Swarm Executor gets the socket. No `0.0.0.0:2375`. No privileged workload, host mount or socket mount for user workloads by default.
- **Untrusted input.** Validate and normalize everything crossing an external boundary — request payloads, webhook bodies, user-supplied URLs, queue payloads. Never deserialize arbitrary classes.
- **SSRF.** Any feature that fetches a URL is a candidate bridge to the Docker API, cloud metadata or internal services. Block loopback, link-local, RFC1918/ULA and metadata endpoints unless the operation genuinely requires internal networking; resolve DNS and validate the final IP; treat a redirect as a new policy decision; reject unexpected schemes.
- **Webhooks.** Validate the signature, enforce a replay window, deduplicate by delivery ID, and limit payload size.
- **Audit.** Every privileged action records actor, resource, action, result, `requestId` and `operationId`.
- **Errors.** Responses returned to users contain no stack trace, SQL, internal path or cryptographic material.

## Observability

An operation is not complete without the signals needed to diagnose it without reproducing it locally.

Minimum correlation fields, where applicable: `request_id`, `operation_id`, `team_id`, `project_id`, `environment_id`, `service_id`, `cluster_id` / `node_id`, `actor_id` / `source`.

- Metrics avoid high-cardinality labels and sensitive values.
- A degraded dependency is surfaced as degraded — never masked as healthy.
- Audit records are append-only and sanitized.

## Testing

Every Story declares the tests it requires. Run the relevant suites — and record their results — **before** marking a Story complete. Annex D is the strategy; the Story is the concrete list.

Minimum classes to consider per change: static checks, unit (domain rules, state machines, policies, diff), integration against **real PostgreSQL** (constraints, transactions, locks, idempotency, outbox, migrations), contract (API, events, providers), Docker/Swarm integration when the change has real runtime effect, and E2E for critical journeys.

Every new mutation needs a negative authorization test, including cross-team access attempts.

A failing test is never resolved by:

- deleting a valid test;
- weakening an assertion;
- disabling a lint or security rule;
- excluding a file from a scanner;
- lowering a threshold;
- changing an acceptance criterion.

Fix the implementation. Changing a gate itself requires its own Story or ADR.

A flaky test is a defect: quarantine it with an owner and a short deadline; never mask it with retries. Intermittent failures in security, restore or concurrency tests block release until understood.

## Dependencies

Before adding a gem or npm package, answer:

```text
Does the approved stack already solve this?
Is there a simple internal solution?
Is the dependency maintained, with an acceptable release and security posture?
Does it duplicate something already installed?
Is it proportional to the problem, or does it drag in an entire platform?
Is the license compatible?
Is it actually necessary for this Story?
```

Any relevant new dependency must be recorded in the Story report with a short justification (problem solved, alternatives evaluated, why they are insufficient, maintenance/security/license, long-term impact) and pinned in the lockfile. "For convenience" is not a justification.

## Refactoring

| Class | Definition | Treatment |
|---|---|---|
| **Required** | The Story cannot be implemented correctly or safely without it. | Do it inside the Story; justify it in the report. |
| **Opportunistic** | Small, local, low-risk, directly adjacent to code already being touched, and immediately reduces complexity. | Allowed only while the diff stays small and tests cover it. |
| **Strategic** | Restructures a module, boundary, data model or set of abstractions. | Never inside another Story. Create its own Story / ADR. |

Debt found but not needed for the Story goes to a structured backlog with impact and evidence — not an open-ended `TODO`. Any `TODO`/`FIXME` must reference a Story or issue and must not hide a critical requirement.

## Git Discipline

```text
1 Story  ≈  1 coherent unit of commit
```

A Story may produce one or a few commits, but every commit must represent a change a reviewer can understand, revert and bisect on its own. Never bundle several independent Stories into one commit.

Commit messages are descriptive and scoped:

```text
feat(service): persist service desired state
feat(reconcile): converge service desired state
test(vault): cover version pin rollback
```

Not: `feat: platform changes`, `fix stuff`, `WIP final`.

Never commit: secrets, tokens, private keys, dumps or fixtures with real data; temporary artifacts, local logs or unintended binaries; out-of-scope changes without explanation; commented-out dead code used as a backup.

Do not bypass hooks. `--no-verify` is never automatic, and an agent may not disable a hook to unblock a Story.

## Quality Gates

```text
Story
  ↓
Implementation
  ↓
Local Quality Gate
  ↓
Reviewer
  ↓
Pre-commit Gate
  ↓
Commit
  ↓
Post-commit Gate
  ↓
Architecture Fitness Functions
  ↓
DONE
```

**Local Quality Gate** — before declaring the implementation ready: format/lint, typecheck, related tests, migration validation, contract/schema tests when a contract changed, and the applicable security checks for the classes of code touched.

**Reviewer** — an independent context compares the diff against Story, architecture, security and tests, looking for correctness, scope creep, boundary violations, missing authorization, missing idempotency, missing audit, weak observability, missing tests and overengineering. Findings are classified Critical / High / Medium / Low.

**Pre-commit Gate** — format, lint, typecheck, fast related tests, secret scan, no obviously invalid migration, no stray generated files, diff within the expected scope.

**Post-commit Gate** — the commit is a coherent change; every acceptance criterion maps to implementation, test or evidence; module tests green; fitness functions green; `Critical = 0` and `High = 0`; task state and Story report consistent with the commit hash.

**Architecture Fitness Functions** — automated invariants (Annex I §16.2): public controllers do not import a Docker client; only the Swarm Executor module references the socket; reconcilers do not write user-intent Desired State columns; the React tree does not import server-only code; the MCP adapter does not call the executor directly; no plaintext secret in serializers, logs or audit payloads; critical mutations have a server-side authorization path; events and operations carry correlation IDs; known destructive migrations require a contract-phase marker/ADR; a React feature does not duplicate an existing primitive without a waiver.

A gate is not editable to make a Story pass. Failing a gate means fixing the implementation, or opening an explicit, versioned, temporary waiver with reason, owner and removal deadline.

`Critical` and `High` findings block DONE and block merge.

## Documentation

- Update documentation when a change alters a contract, a decision or an operational procedure — not for every commit.
- A new architectural decision with systemic impact becomes an ADR in `docs/decisions/` **before** it becomes an implicit pattern: technology change, contract change between modules, new consistency/concurrency rule, security-boundary change, or a permanent exception to an existing invariant.
- Do not silently rewrite approved specification documents to match an implementation. Record the conflict instead.
- Keep `docs/MASTER.md` accurate as a map. Do not copy architecture documents into `CLAUDE.md`, `AGENTS.md` or this file — the invariants restated in "Architecture Invariants" are a deliberate short list, not a second specification. The architecture documents remain the source.
- Known divergences between the converted specification and current decisions are tracked in `docs/decisions/pending-documentation-updates.md`. Consult it before treating a document's stack statement as current.

## Specification Conflicts

When documentation, Story and implementation disagree:

```text
1. do not choose silently;
2. record the conflicting file and section;
3. explain the impact (contract, security, persistence, architecture, UX);
4. apply the most recent decision only when it is unambiguous;
5. otherwise mark the affected work BLOCKED.
```

Rules:

- Stop **only the affected part**. Continue with independent work in the same Story or Milestone.
- A conflict that touches contract, security, persistence or architecture is never resolved by inventing a new pattern.
- An ambiguous product requirement is `BLOCKED_FOR_PRODUCT_DECISION`.
- A destructive or production-facing action is `BLOCKED_FOR_HUMAN_APPROVAL`.
- An unavailable external dependency is `BLOCKED_EXTERNAL_DEPENDENCY`.
- Repeated failure without progress converges to `BLOCKED` with a reproducible diagnosis — never an infinite loop.
- Resolving a conflict in favour of a new decision requires an ADR, not an edit to the specification made in passing.
