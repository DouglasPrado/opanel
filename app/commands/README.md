# app/commands

Explicit business mutations. A Command is the single place where a relevant
change of intent is authorized, validated, persisted and audited.

Dependency rule: `controllers → commands | queries → models`.

## Responsibility

- Orchestrate one business mutation, transactionally when the invariant demands it.
- Write Desired State, the `Operation` and the `OutboxEvent` in the same transaction.
- Return a typed result the caller can branch on.
- Be reusable by every delivery channel: Inertia controllers, public API, CLI and MCP
  call the same Command.

## Prohibitions

- No HTTP rendering, no knowledge of Inertia, params or views.
- No Docker Engine call. Infrastructure effects go through an `Operation` and a
  Reconciler; only `app/executors/` talks to the Docker API.
- No network call inside a database transaction.
- No plaintext secret in `Operation` payloads, events or audit records — reference
  a `SecretVersion` id instead.
- Do not create a Command for a trivial setter with no rule (Annex I §5).

## References

- `docs/AGENT_RULES.md` — "Backend Rules", "Async Operations"
- `docs/annexes/I-engineering-playbook-quality-gates.md` §4.1, §5
