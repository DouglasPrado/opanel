---
title: "Opanel — Operational templates"
type: "templates-index"
---

# Operational templates

Versioned templates for the decision and evidence artifacts that Annex G §20/§22,
Annex H §9.2 and Annex I §23 require. They exist so traceability does not depend
on how each session decides to write.

These paths are **stable**. The Post-commit Gate (`bin/gate post-commit`) and the
Stop Gate (`bin/stop-gate`) reference them literally; renaming a file here breaks
a gate and requires its own Story.

| Artifact | Template | Produced at |
|---|---|---|
| Architecture Decision Record | [`ADR.md`](ADR.md) | `docs/decisions/ADR-<NNNN>-<slug>.md` |
| Story Report | [`STORY_REPORT.md`](STORY_REPORT.md) | `docs/implementation/M<XX>/reports/<story>.md` |
| Milestone Report | [`MILESTONE_REPORT.md`](MILESTONE_REPORT.md) | `docs/implementation/M<XX>/MILESTONE_REPORT.md` |
| Dependency Justification | [`DEPENDENCY_JUSTIFICATION.md`](DEPENDENCY_JUSTIFICATION.md) | inside the Story Report |
| Review Findings | [`REVIEW_FINDINGS.md`](REVIEW_FINDINGS.md) | `docs/implementation/M<XX>/review/<story>.md` |
| Blocker | [`BLOCKER.md`](BLOCKER.md) | `docs/implementation/M<XX>/BLOCKERS.md` |
| Commit convention | [`COMMIT_CONVENTION.md`](COMMIT_CONVENTION.md) | every commit message |

## Prohibited content

**No report, review, blocker, ADR or archived evidence may contain sensitive
material.** This is not advisory — the secret scan runs over
`docs/implementation/**` and over the evidence directories, and a hit blocks the
commit (Annex C §17).

Never write into these artifacts:

```text
plaintext secret or SecretVersion value
API token, session cookie, Authorization header
private key or certificate key material
Recovery Key, or any share of it
provider credential (DNS, registry, cloud, git host)
database URL containing a password
real customer data or PII
```

Redact **before** archiving, not after. When evidence must show that a value was
present, record its shape (`length`, `prefix`, `sha256` of a salted digest) — never
the value.

## Rules that apply to all templates

- Every section in a template is required. Removing one is a review finding; the
  section may be answered with `none` or `n/a`, but it may not disappear.
- Evidence means **command executed + result + exit code**. "Tests passed" is not
  evidence and the Post-commit Gate rejects it under `acceptance mapping`.
- Reports describe what happened, not what was intended. A skipped step is written
  down as skipped.
