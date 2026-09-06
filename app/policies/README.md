# app/policies

Server-side, contextual authorization. Deny by default.

## Responsibility

- Answer "may this actor do this to this resource, in this Team / Project /
  Environment context?" with the scope explicitly loaded.
- Be the single authorization path shared by the UI, the public API, the CLI and MCP.
- Ship with a negative authorization test for every new mutation, including a
  cross-team attempt.

## Prohibitions

- Never execute the operation itself — a Policy decides, a Command acts.
- Never rely on the UI, on route shape or on an opaque id for enforcement.
- No implicit allow: a missing rule denies.

## References

- `docs/AGENT_RULES.md` — "Policies", "Security"
- `docs/annexes/C-threat-model-security-hardening.md` §7.3
- `docs/annexes/I-engineering-playbook-quality-gates.md` §4.1, §19.1
