# app/executors

**The only boundary in this repository authorized to talk to the Docker Engine API.**

This is a Tier-0 security invariant (Annex C §8), not a layering preference.
Fitness function **AF-02** fails the build when any file outside `app/executors/`
references `docker.sock` or a privileged Docker client — and it is expected to run
green vacuously until the first executor exists.

## Responsibility

- Expose typed, allowlisted operations (create service, update service, scale,
  inspect tasks, drain node, ...) — one method per intent.
- Run manager-only, with no public route.
- Normalize Docker errors into the platform's error taxonomy.

## Prohibitions

- **No `exec(command: String)` primitive.** There is no generic passthrough.
- No product authorization decisions here — a Policy already decided upstream.
- No public HTTP entry point; the executor is reached from Reconcilers and workers.
- No component outside this directory mounts or reads `/var/run/docker.sock`.
  The disposable Swarm Lab test harness (`bin/swarm-lab`, `spec/support/swarm_lab`)
  is the single, explicitly registered exception, and it may only point at the lab.

## References

- `docs/AGENT_RULES.md` — "Architecture Invariants", "Security"
- `docs/annexes/C-threat-model-security-hardening.md` §8
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-01, AF-02)
