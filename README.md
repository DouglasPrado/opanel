# Opanel

Cluster-first PaaS built on Docker Swarm. This repository holds the Control
Plane: a single Rails 8.1 application that serves its interface with Inertia +
React/TypeScript and reconciles Desired State (PostgreSQL) toward Actual State
(Docker Swarm).

## Bootstrap

```bash
bin/setup
```

`bin/setup` is idempotent: it installs dependencies, prepares the database,
installs the git hooks and leaves the workspace ready. `bin/dev` then starts the
web server, the Solid Queue worker and Vite together.

> The single-command bootstrap is completed by **M00-06**. Until that Story is
> done, follow the manual steps below.

Prerequisites, environment reset and teardown are documented by M00-06.

### Manual steps (until M00-06)

```bash
bundle install
bin/rails server
```

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

## Documentation

| Need | Read |
|---|---|
| Which document decides this? | [`docs/MASTER.md`](docs/MASTER.md) |
| How must this be built? | [`docs/AGENT_RULES.md`](docs/AGENT_RULES.md) |
| What is being built now? | [`docs/implementation/`](docs/implementation/README.md) |
| Process, gates and review | [`docs/annexes/I-engineering-playbook-quality-gates.md`](docs/annexes/I-engineering-playbook-quality-gates.md) |
| Accepted decisions | [`docs/decisions/`](docs/decisions/) |

## Tests

```bash
bundle exec rspec
```

The full harness — real PostgreSQL isolation, component tests, E2E and the
quality gates — is delivered across M00-07 through M00-13.
