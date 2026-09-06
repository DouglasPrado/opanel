# app/operations

Durable records of infrastructure intent. An `Operation` is what makes an
infrastructure mutation asynchronous, resumable and auditable.

## Responsibility

- Persist the intent to change infrastructure, with `schemaVersion`, correlation
  identifiers and the target resource.
- Be created in the same transaction as the Desired State change and the
  `OutboxEvent`; publishing to the queue happens after the commit.
- Carry the state machine that lets a worker resume, supersede or fail an
  operation deterministically.

## Prohibitions

- PostgreSQL — not the queue — is the source of truth about an Operation. Never
  assume the broker delivers exactly once.
- No plaintext secret in a payload: reference `SecretVersion` ids.
- No direct Docker Engine call from here.
- Never hold an HTTP request open waiting for an Operation to finish.

## References

- `docs/AGENT_RULES.md` — "Async Operations"
- `docs/architecture/07-internal-control-plane.md` §9, §10
