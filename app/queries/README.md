# app/queries

Optimized reads and read-model composition.

Dependency rule: `controllers → commands | queries → models`.

## Responsibility

- Compose the read models that pages and API responses need.
- Own the index strategy for the operational queries they run.
- Paginate anything that can grow without bound.
- Scope every read by the tenancy chain (Team / Project / Environment) rather
  than fetching by id and trusting the route.

## Prohibitions

- Never mutate domain state.
- No Docker Engine call.
- No N+1 or unbounded collection load in an interactive request.
- Do not create a Query Object for a trivial query that gains nothing from it.

## References

- `docs/AGENT_RULES.md` — "Backend Rules", "Database Rules"
- `docs/annexes/I-engineering-playbook-quality-gates.md` §4.1, §8.1
