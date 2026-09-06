---
title: "Template — Architecture Decision Record"
type: "template"
---

# Template — Architecture Decision Record

Copy to `docs/decisions/ADR-<NNNN>-<kebab-slug>.md`. `<NNNN>` is the next free
sequential number; numbers are never reused, and a superseded ADR stays in place
with `Status: Superseded by ADR-<NNNN>`.

## When an ADR is required

An ADR is written **before** the decision becomes an implicit pattern in the code
(Annex G §20). Required when the change is any of:

| Trigger | Example |
|---|---|
| Structural technology change | Replacing a layer of the approved stack. |
| Contract change between modules | New event schema, new executor operation shape. |
| New consistency or concurrency rule | Lease semantics, ordering guarantee, idempotency scope. |
| Security boundary change | Who may reach the Docker socket, where a secret is decrypted. |
| Permanent exception to an existing invariant | Anything a fitness-function waiver would otherwise hide forever. |

A local implementation choice inside one Story is **not** an ADR. Record it under
"Decisões locais" in the Story Report instead.

`Status` values: `Proposed` · `Accepted` · `Rejected` · `Superseded`.
A `Proposed` ADR blocks any Story that depends on the decision. Only a human moves
an ADR to `Accepted`.

**No sensitive content.** See [`README.md`](README.md) — an ADR that names a
credential, key or token is blocked by the secret scan.

---

```markdown
---
title: "ADR-<NNNN> — <short title>"
status: "Proposed"
date: "<YYYY-MM-DD>"
decision-required-before: "<Story id, or none>"
---

# ADR-<NNNN> — <short title>

**Status:** `Proposed` — <who must accept it, and before what>

## Context

<The forces that make a decision necessary. Quote the specification sections that
conflict or that leave the question open, by file and section. State what is
already decided and must not be relitigated.>

## Decision

<The decision, in one paragraph, in the imperative. Precise enough that two
engineers would implement the same thing.>

## Consequences

<What becomes true, what becomes harder, what has to change. Include the
irreversible parts explicitly, and the migration cost if the decision is later
reversed.>

## Alternatives considered

| Alternative | Why it was not chosen |
|---|---|
| <option> | <reason> |

## Affected docs

- `<path>` §<section> — <what needs to change there>

## Affected modules

- `<path or boundary>` — <what changes>
```
