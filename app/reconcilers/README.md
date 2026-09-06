# app/reconcilers

Convergence of Actual State (Docker Swarm) toward Desired State (PostgreSQL).

Dependency rule: `reconcilers → executors`.

```text
read Desired State → read Actual State → diff → smallest safe operation → persist observation
```

## Responsibility

- Re-read reality every run; correctness comes from observation, not from an
  uninterrupted event stream.
- Hold a lease with a fencing token, act, then re-inspect the runtime.
- Classify every diff as `NOOP`, `CREATE`, `UPDATE_SAFE`, `ROLLOUT`, `DELETE`,
  `BLOCKED` or `DRIFT`.
- Stay small, deterministic and resumable; keep no state in process memory.

## Prohibitions

- Never write a Desired State column that represents user intent. Platform Wins is
  the default drift policy; adopting runtime state is an explicit admin operation.
- Never promote Actual State into the source of truth.
- Never adopt or delete a resource that carries no platform ownership label.
- Never call the Docker socket directly — go through `app/executors/`.

## References

- `docs/AGENT_RULES.md` — "Reconciliation", "Architecture Invariants"
- `docs/architecture/07-internal-control-plane.md`
