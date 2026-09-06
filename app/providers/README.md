# app/providers

Adapters that isolate external APIs: DNS providers, OCI registries, Git hosts,
ACME, object storage, load balancers.

## Responsibility

- Wrap one external API behind a contract expressed in the platform's own terms.
- Normalize errors, timeouts and retry semantics into the shared taxonomy.
- Keep credentials as `SecretVersion` references resolved at call time.
- Apply the SSRF policy on every user-supplied URL: resolve DNS, validate the final
  IP, treat a redirect as a new decision, reject unexpected schemes.

## Prohibitions

- Never leak a vendor SDK type into the domain, a Command or a serializer.
- Never talk to the Docker Engine API — that is `app/executors/`.
- Do not create a new adapter, retry helper or error envelope before checking that
  an existing one covers the case (Annex I §20.1).

## References

- `docs/AGENT_RULES.md` — "Provider adapters and the Swarm Executor", "Security"
- `docs/annexes/I-engineering-playbook-quality-gates.md` §4.1, §20.1
