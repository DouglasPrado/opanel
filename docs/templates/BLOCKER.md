---
title: "Template — Blocker"
type: "template"
---

# Template — Blocker

Append a block to `docs/implementation/M<XX>/BLOCKERS.md` whenever a Story moves
to `blocked`. The same qualifier goes into `tasks.json` as `blockedReason`.

A blocked Story is never abandoned silently: the loop records the diagnosis,
continues with independent Stories, and the Milestone Report lists it.

## Valid qualifiers

| Qualificador | Quando |
|---|---|
| `BLOCKED_FOR_PRODUCT_DECISION` | An ambiguous product requirement, or a `Proposed` ADR the Story depends on. |
| `BLOCKED_FOR_HUMAN_APPROVAL` | The next step is destructive or production-facing. |
| `BLOCKED_EXTERNAL_DEPENDENCY` | An external repository, service or credential is unavailable. |

No other value is accepted by the `tasks.json` schema.

## Attempt policy

Three attempts without progress on the same failure → change strategy **once** →
if there is still no progress, `blocked` with a reproducible diagnosis. Repeating
the same failing approach is itself a finding.

**No sensitive content.** See [`README.md`](README.md) — a blocker caused by a
missing credential names the variable, never the value.

---

```markdown
## <STORY-ID> — <title>

- **Qualificador:** `BLOCKED_FOR_PRODUCT_DECISION` | `BLOCKED_FOR_HUMAN_APPROVAL` | `BLOCKED_EXTERNAL_DEPENDENCY`
- **Data:** `<YYYY-MM-DD>`
- **Tentativas:** <n>

### Diagnóstico reproduzível

```text
<command>
<exit code and the relevant output, redacted>
```

<Why this is a block and not a bug to fix: what was tried, what changed between
attempts, and why the second strategy also failed.>

### O que destravaria

- <the specific decision, approval or artifact needed>
- <who can provide it>

### Trabalho independente que continuou

- <Stories that were not affected and moved forward>
```
