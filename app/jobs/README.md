# app/jobs

Asynchronous execution over Solid Queue.

## The rule that matters most: the broker is not durable

**The queue is a delivery mechanism. PostgreSQL is the source of truth.**

If a message is lost, **no intent may be lost with it.** Durability belongs to the
`Operation` row in PostgreSQL, and the recovery sweep of `M01-15` finds Operations
left `QUEUED`/`RUNNING` without a valid lease and re-enqueues them. Solid Queue
storing its own tables in the same PostgreSQL does not change this: a job row is
delivery state, never user intent (doc 07 §9.2, SC-02).

Consequently:

- **No job may assume exactly-once delivery.** Every job that produces a repeatable
  effect must converge when it runs twice.
- A job that cannot be made idempotent must observe Actual State before repeating a
  non-idempotent effect (`docs/AGENT_RULES.md`, "Async Operations").
- Losing a job must never be the reason a user's change disappears. If that is
  possible, the durability is in the wrong place.

## Responsibility

- **Hand off to the Application Layer.** A Job calls a Command; it does not restate
  the Command's business rules (Annex I §4.1).
- Declare its own retry policy with `retry_policy on:, attempts:, wait:`. There is
  no global default — a job that declares nothing does not retry, and no policy is
  unbounded.
- Validate its payload before applying any effect, and raise `InvalidPayload` for
  input it cannot trust. That is discarded, never retried.
- Run on one of the six logical queues named in `lib/opanel/queues.rb`
  (doc 07 §9.1): `deployments`, `runtime`, `cluster`, `certificates`, `backup-dr`,
  `system`.

## Prohibitions

- **No business rule duplicated from a Command.**
- **No plaintext secret in a payload.** Arguments are serialized, stored in
  PostgreSQL and visible to anyone who can read the queue tables — pass a
  `SecretVersion` id. `ApplicationJob` never logs arguments, and AF-06 (M00-13)
  enforces the rule beyond this directory.
- **No arbitrary class in a payload.** Active Job only serializes primitives and
  GlobalIDs; do not widen that (Annex C §16).
- No unbounded retry, and no `rescue` that turns a failure into a success.
- No direct Docker Engine call — that is `app/executors/`, reached through a
  Reconciler.

## What a job logs

`ApplicationJob` emits one structured entry per execution with `event`,
`job_class`, `job_id`, `queue`, `attempt`, `result`, `duration_ms` and the
`correlation_id` captured from whoever enqueued it. Terminal failures and discarded
payloads are separate events. Arguments are never logged.
