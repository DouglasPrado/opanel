# Opanel

Cluster-first PaaS built on Docker Swarm. This repository holds the Control
Plane: a single Rails 8.1 application that serves its interface with Inertia +
React/TypeScript and reconciles Desired State (PostgreSQL) toward Actual State
(Docker Swarm).

## Getting started

```bash
bin/setup
```

That is the whole thing. It checks the prerequisites, installs the gems and npm
packages, prepares the databases, seeds synthetic development data, installs the
git hooks, and starts `bin/dev`.

It is **idempotent**: running it again is safe and leaves the same state. If a
prerequisite is missing it stops immediately and says which one and what to do
about it, rather than failing forty lines into a build.

### Prerequisites

| Tool | Version | Why |
|---|---|---|
| Ruby | ≥ 3.2 (this repository pins `.ruby-version`) | The Control Plane. |
| Node.js | ≥ 20 | The Vite toolchain. |
| PostgreSQL | ≥ 16, running | Desired State. `bin/setup` checks it is accepting connections, not merely installed. |
| Docker | ≥ 24 | Only for the Swarm Lab (`bin/swarm-lab`) and the tests that use it. |

No credential is needed to run locally. `bin/setup` refuses to run at all if it
finds a production credential in the workspace (Annex H §3.2).

### Running it

```bash
bin/dev
```

Starts three processes in one supervised foreground command — the web server on
`http://localhost:3000`, the Solid Queue worker, and Vite on `:3036` — with each
one's output labelled. **If any of them dies, it says which and stops the
others**, so a silently dead worker is not something you discover twenty minutes
later. Override a port with `PORT=` or `VITE_RUBY_PORT=`; an occupied port is
reported with the process holding it.

`GET /up` reports the application, PostgreSQL and the queue separately.

### Resetting and destroying the environment

```bash
bin/setup --reset          # drop and recreate the databases, then seed
bin/rails db:drop          # destroy the databases and stop
```

Nothing else on your machine is touched: the gems live in `vendor/bundle`, the
npm packages in `node_modules`, and both are git-ignored. Deleting the clone
removes everything except the PostgreSQL databases, which `bin/rails db:drop`
handles. The Swarm Lab is separate and is destroyed with `bin/swarm-lab down`.

## Commands

| Command | What it does |
|---|---|
| `bin/setup` | Set up or update the environment. Idempotent. |
| `bin/dev` | Web server, job worker and Vite, supervised together. |
| `bin/test` | Backend suite. `--type`, `--parallel`, `--changed`, `--seed`. |
| `bin/test:js` | Component tests (Vitest). |
| `bin/test:e2e` | Browser journeys (Playwright). |
| `bin/lint` · `bin/format` · `bin/typecheck` | The static gates. `--changed` for the pre-commit scope. |
| `bin/migration-gate` | Reversibility, contract phase and index safety. |
| `bin/workspace-guardrail` | No production credential in the workspace. |
| `bin/jobs` | The Solid Queue worker on its own. |

Every gate accepts `--format json`. Their time budget is measured and recorded in
[`docs/engineering/quality-gates.md`](docs/engineering/quality-gates.md).

## Layout

| Path | Boundary |
|---|---|
| `app/controllers/` | Receive the request, authenticate context, call the Application Layer, render. |
| `app/commands/` | Explicit business mutations. |
| `app/queries/` | Optimized reads and read models. |
| `app/policies/` | Server-side authorization. |
| `app/operations/` | Durable records of infrastructure intent. |
| `app/reconcilers/` | Converge Actual State toward Desired State. |
| `app/executors/` | The only boundary allowed to reach the Docker Engine API. |
| `app/providers/` | Adapters isolating external APIs. |
| `app/frontend/` | React/TypeScript tree bundled by Vite. |

Every boundary directory carries a `README.md` stating its responsibility and its
prohibitions. Dependency rules: `controllers → commands | queries → models`,
`reconcilers → executors`, and `providers` isolate external APIs without leaking
their SDKs into the domain.

Before creating a UI component, read
[`app/frontend/components/INVENTORY.md`](app/frontend/components/INVENTORY.md).
The Reuse Gate is evaluated against it, and `/gallery` renders every entry in
development.

## Documentation

| Need | Read |
|---|---|
| Which document decides this? | [`docs/MASTER.md`](docs/MASTER.md) |
| How must this be built? | [`docs/AGENT_RULES.md`](docs/AGENT_RULES.md) |
| What is being built now? | [`docs/implementation/`](docs/implementation/README.md) |
| Process, gates and review | [`docs/annexes/I-engineering-playbook-quality-gates.md`](docs/annexes/I-engineering-playbook-quality-gates.md) |
| Suppressing a lint rule | [`docs/engineering/lint-suppressions.md`](docs/engineering/lint-suppressions.md) |
| An intermittent test | [`docs/engineering/flaky-tests.md`](docs/engineering/flaky-tests.md) |
| Accepted decisions | [`docs/decisions/`](docs/decisions/) |
