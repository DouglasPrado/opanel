---
title: "Quality gates — entry points and time budget"
type: "engineering-convention"
---

# Quality gates — entry points and time budget

Every check has one command. A gate that has to be remembered is a gate that gets
skipped.

| Command | What it runs |
|---|---|
| `bin/lint` | RuboCop, ESLint, and the Suppression Gate. |
| `bin/format` | RuboCop layout autocorrect and Prettier. `--check` reports without writing. |
| `bin/typecheck` | `tsc --noEmit` over `app/frontend/`. |
| `bin/migration-gate` | Reversibility, contract phase and index safety (Annex I §8.2). |
| `bin/suppression-gate` | A silenced rule names the Story or ADR that allows it. |

Each accepts `--format json` and reports, per check, its name, result, duration
and the reason it failed. The Stop Gate (M00-14) parses that; a human reads the
text form. `bin/gate local|pre-commit|post-commit` (M00-12) composes them.

## Scope

`--changed` limits the work to files that differ from the merge base with the
default branch, plus anything staged. `OPANEL_GATE_BASE` overrides the base
branch. Without it, the whole repository is checked.

`bin/typecheck` has no incremental mode, and adding one would be dishonest:
TypeScript resolves the whole program to answer anything about one file.

## Time budget

Measured on the reference machine (Apple Silicon, warm caches), on a diff of
**20 files** — a typical Story:

| Check | Typical diff | Whole repository |
|---|---|---|
| `bin/lint` | **1.2 s** | 2.4 s |
| `bin/format --check` | **0.7 s** | 1.1 s |
| `bin/typecheck` | 1.6 s | 1.6 s |
| `bin/migration-gate` | < 0.1 s | < 0.1 s |

**Budget: `bin/gate pre-commit` stays under 10 seconds on a typical diff.**

The number matters because of what happens when it is missed. A pre-commit gate
that takes a minute gets bypassed, and a bypassed gate protects nothing
(Annex I §12.1). When a check outgrows the budget, it moves to CI — it is never
removed, and the ruleset is never loosened to buy time (Annex I §21.2).

Re-measure with:

```bash
OPANEL_GATE_BASE=HEAD bin/lint --changed --format json
```

## Silencing a rule

See [`lint-suppressions.md`](lint-suppressions.md). Short version: a suppression
names a Story or an ADR, or `bin/lint` fails.
