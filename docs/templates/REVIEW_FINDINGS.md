---
title: "Template — Review Findings"
type: "template"
---

# Template — Review Findings

Copy to `docs/implementation/M<XX>/review/<story-id>.md`. One file per Story.

This is the **implementation quality self-review** of a Story: an explicit pass
over the diff against the Story, the architecture, security and tests. It is not,
and cannot substitute for, the independent Milestone review — that verdict is
written only by the orchestrator, in `CODEX_REVIEW_<NN>.md` (ADR-0003).

## Severities and blocking policy

| Severidade | Exemplo | Política |
|---|---|---|
| **Critical** | Authorization bypass, secret leak, data loss, undue `docker.sock` access. | **Blocks commit, DONE and merge.** Fix before anything else. |
| **High** | Race with a real effect, unsafe migration, missing idempotency on a critical operation. | **Blocks DONE and merge.** |
| **Medium** | Fragile design, meaningful duplication, insufficient observability. | Fix, or record a waiver/Story with owner and deadline. |
| **Low** | Naming, small simplification, non-functional polish. | May become a follow-up if debt does not accumulate. |

`Critical = 0` and `High = 0` are required before a Story is `done` and before any
merge. They are checked by the Post-commit Gate and by the Stop Gate.

## Review dimensions (Annex I §17.1)

Correção · Escopo · Arquitetura · Simplicidade · Reuso · Segurança · Concorrência ·
Dados · Observabilidade · Testes · Operação.

Every dimension is answered. `no finding` is a valid answer; silence is not.

**No sensitive content.** See [`README.md`](README.md) — describe a leak by file
and line, never by reproducing the value.

---

```markdown
# Review — <STORY-ID> <title>

- Reviewed diff: `<base>..<head>`
- Reviewer: implementer self-review (Annex I §17.1)
- Date: `<YYYY-MM-DD>`

## Dimensões

| Dimensão | Resultado |
|---|---|
| Correção | no finding / see F-<n> |
| Escopo | no finding / see F-<n> |
| Arquitetura | no finding / see F-<n> |
| Simplicidade | no finding / see F-<n> |
| Reuso | no finding / see F-<n> |
| Segurança | no finding / see F-<n> |
| Concorrência | no finding / see F-<n> |
| Dados | no finding / see F-<n> |
| Observabilidade | no finding / see F-<n> |
| Testes | no finding / see F-<n> |
| Operação | no finding / see F-<n> |

## Findings

### F-1 — <short title>

- **Dimensão:** <dimension>
- **Severidade:** Critical | High | Medium | Low
- **Evidência:** `<file>:<line>` — <what is wrong, and how it was observed>
- **Ação:** fixed in `<commit>` | waiver `<id>` | follow-up Story `<id>`
- **Estado:** closed | open

## Contagem

| Severidade | Abertos |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | <n> |
| Low | <n> |
```
