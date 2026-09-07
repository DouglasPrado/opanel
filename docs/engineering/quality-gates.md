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
| `bin/suppression-gate` | A silenced rule names the Story or ADR that allows it, and a control turned down in configuration has an owned, dated waiver. |
| `ruby bin/dependency-gate` | A dependency added since the base branch is justified in a Story Report or ADR, and pinned in the lockfile (Annex I §10). |
| `bin/ci-job <job>` | One CI job, exactly as CI runs it. `--list` shows them all. |
| `bin/merge-gate` | The Merge Gate checklist of Annex I §15.2, executed. |
| `bin/flaky-rate` | Flaky rate and top offenders across archived runs. |

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

Measured on the reference machine (Apple Silicon, warm caches). "Typical diff" is
a handful of files against the merge base — one increment of a Story, which is
what the hook actually sees:

| Check | Typical diff | Whole repository |
|---|---|---|
| `bin/format --check` | **0.5 s** | 1.1 s |
| `bin/lint` | **0.6 s** | 2.9 s |
| `bin/typecheck` | 1.8 s | 1.8 s |
| `bin/test --changed --fast` | **0.4 s** | 39 s |
| `bin/security --fast --staged` | **0.2 s** | 9.2 s |
| `bin/migration-gate` | < 0.1 s | < 0.1 s |
| `bin/gate pre-commit` (all eight) | **3.8 s** | — |

**Budget: `bin/gate pre-commit` stays under 10 seconds on a typical diff.**
Measured at **3.8 s**.

> The table above was measured before the fixes of `FIX_REPORT_01.md`, which added
> the allowlist check to `bin/security --fast` and made `bin/test --changed`
> select the *related* specs rather than only the changed ones. Both move the
> number. **Re-measure before trusting it** — a budget nobody has re-run since the
> code changed is a number, not a measurement.

Two of those numbers are the difference between a gate people run and a gate
people work around, and both were bought by narrowing *scope*, never by removing
a check:

- the secret scan reads the **staged diff** (`gitleaks git --staged`) rather than
  the whole tree — which is exactly the question a pre-commit gate asks. The
  `security-fast` CI job still scans everything, and the history with it;
- the test step skips `:slow` examples — the gate suites, which run RuboCop,
  gitleaks and RSpec against planted failures to prove those gates can fail. CI
  runs them on every push.

`--changed` compares against the merge base, so on a branch that has added four
hundred specs it selects four hundred specs. That is the branch being large, not
the gate being slow.

The number matters because of what happens when it is missed. A pre-commit gate
that takes a minute gets bypassed, and a bypassed gate protects nothing
(Annex I §12.1). When a check outgrows the budget, it moves to CI — it is never
removed, and the ruleset is never loosened to buy time (Annex I §21.2).

Re-measure with:

```bash
OPANEL_GATE_BASE=HEAD bin/lint --changed --format json
```

## In CI

The same commands, scheduled by `config/ci/jobs.yml` — see
[`ci-pipeline.md`](ci-pipeline.md). Nothing runs in CI that cannot be run here by
name, which is why a local green and a CI red are worth investigating rather
than shrugging at.

## Silencing a rule

See [`lint-suppressions.md`](lint-suppressions.md). Short version: a suppression
names a Story or an ADR, or `bin/lint` fails.

A control turned down in a **configuration** file leaves no line to comment on —
an ESLint rule switched off for a directory, a TypeScript flag left out, an
accessibility violation added to a baseline. Those go in
`config/quality/waivers.yml`, on the same contract as the security waivers: risk,
owner, justification, mitigation and an expiry. `bin/suppression-gate` fails on a
reduction with no waiver **and on a waiver that has expired**, which is the whole
mechanism — otherwise a temporary relaxation becomes permanent by nobody
deciding anything.
