---
title: "Convenção de commits"
type: "convention"
---

# Convenção de commits

A commit is a coherent, reversible checkpoint. One Story produces one — or a few —
commits, and each one must be understandable, revertible and bisectable on its own
(Annex I §13.1).

## Format

```text
<type>(<scope>): <imperative summary, lower case, no trailing period>

<body: what changed and why. Wrap at 72 columns. Explain the reasoning that is
not visible in the diff — the constraint, the alternative rejected, the invariant
being protected.>

Story: <STORY-ID>
```

`<type>` is one of:

| Type | Use |
|---|---|
| `feat` | New behaviour. |
| `fix` | Corrects behaviour that was wrong. |
| `refactor` | Same behaviour, better structure. Required or opportunistic only (Annex I §18.1). |
| `test` | Adds or changes tests only. |
| `docs` | Documentation, ADRs, Implementation Pack. |
| `chore` | Tooling, dependencies, repository plumbing. |
| `perf` | Measured performance change, with the evidence in the body. |

`<scope>` is the boundary or subsystem touched: `service`, `reconcile`, `vault`,
`executor`, `frontend`, `gate`, `pack`, `ci`.

## Good

```text
feat(service): persist service desired state
feat(reconcile): converge service desired state
test(vault): cover version pin rollback
fix(executor): reject task inspect without ownership label
docs(adr): record ULID identifier strategy
```

Each one names a subject and a verb. A reviewer can predict the diff from the
subject line and revert it without reading the body.

## Bad

```text
feat: platform changes        # which platform, which change?
fix stuff                     # no type, no scope, no subject
WIP final                     # not a checkpoint
update                        # says nothing
feat(service): changes        # scope without a subject
misc fixes and refactor       # several independent Stories in one commit
```

## Rules

- **No sensitive content**, in the message or in the diff. See
  [`README.md`](README.md) for the full list; the secret scan in the Pre-commit
  Gate blocks the commit and a leaked value is treated as compromised — rotated,
  not merely removed from the commit.
- **Never bundle independent Stories** into one commit.
- **Never commit:** secrets, tokens, private keys, dumps or fixtures with real
  data; temporary artifacts, local logs or unintended binaries; out-of-scope
  changes without explanation; commented-out dead code kept as a backup
  (Annex I §13.2).
- **Never bypass hooks.** `--no-verify` is never automatic and an agent may not
  disable a hook to unblock a Story (Annex I §12.2). The Post-commit Gate detects
  a commit that did not pass the Pre-commit Gate.
- A commit that changes a gate, a checker or the CI definition needs its own Story
  or ADR and says so in the body (Annex I §21.2).
- Co-authorship trailers go after the `Story:` line.
