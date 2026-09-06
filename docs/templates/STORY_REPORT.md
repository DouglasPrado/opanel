---
title: "Template — Story Report"
type: "template"
---

# Template — Story Report

Copy to `docs/implementation/M<XX>/reports/<story-id>.md`. One report per Story,
written at closure, covering the items of Annex G §22.

The report is the input a reviewer reads instead of re-deriving the reasoning. It
must be truthful about what was *not* done.

**Evidence rule:** every test and check line records the command and its exit
code. `PASS` without a command is rejected by the Post-commit Gate.

**No sensitive content.** See [`README.md`](README.md). Redact command output
before pasting it.

---

```markdown
# Story Report — <STORY-ID> <title>

## Resultado

- Story: `<STORY-ID>` — <title>
- Status: `completed` | `blocked` | `partial`
- Commit: `<hash>`
- Milestone: `M<XX>`

## Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `<path>` | <one line> |

## Schema / API / Events

- Schema: <migrations, constraints, indexes — or `none`>
- API: <endpoints or contracts changed — or `none`>
- Events: <event types and versions — or `none`>

## Decisões locais

- <decision and why; anything with systemic impact must have become an ADR instead>

## Testes executados

| Comando | Resultado | Exit code |
|---|---|---|
| `<command>` | PASS/FAIL | `0` |

## Quality Gates

| Gate | Resultado | Exit code |
|---|---|---|
| `bin/gate local` | PASS/FAIL | `0` |

## Acceptance Criteria

- [ ] 1. <criterion> — evidence: <command / test / file>
- [ ] 2. <criterion> — evidence: <command / test / file>

## Dependências novas

<One Dependency Justification block per new dependency, per
[`DEPENDENCY_JUSTIFICATION.md`](DEPENDENCY_JUSTIFICATION.md). Write `none` when
nothing was added — never leave the section out.>

## Pendências / conflitos

- <specification conflict found, with file and section, and what was stopped>
- <work deliberately left to another Story, and which one>
- `none` when there is nothing.
```
