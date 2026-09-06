---
title: "Suppressing a lint or security rule"
type: "engineering-convention"
---

# Suppressing a lint or security rule

A rule can be silenced. It cannot be silenced **anonymously**.

Annex I §21.2 is the reason: an agent may fix code to satisfy a gate, but it may
not weaken the gate to get past one. Without a written reason, `# rubocop:disable`
and `// eslint-disable-next-line` become the cheapest way to make any checker
green, and the ruleset decays one commit at a time with nobody able to say when it
started.

`bin/lint` runs the **Suppression Gate** over every tracked file and fails on a
suppression that names no Story and no ADR.

## The rule

Every suppression carries a reason **and** a reference to a Story (`M01-14`), an
ADR (`ADR-0002`) or an issue (`#123`), on the suppression line itself or on the
comment directly above it.

### Ruby

```ruby
# rubocop:disable Metrics/AbcSize -- M01-14: the state machine reads worse split
def transition(...)
end
# rubocop:enable Metrics/AbcSize
```

```ruby
# M03-07: the Vault envelope needs the raw bytes; the cop cannot see that the
# value never leaves this method.
# rubocop:disable Opanel/SilentRescue
```

### TypeScript

```ts
// eslint-disable-next-line no-restricted-imports -- M09-03: the metrics adapter
// runs in Node, not in the browser tree
import { hostname } from 'node:os';
```

### Anything else

`# nosec`, `# brakeman:ignore` and `// @ts-expect-error` follow the same rule.

## What a good reason looks like

It says **why the rule does not apply here**, not that it is inconvenient.

| Good | Bad |
|---|---|
| `M01-16: the fencing token comparison must stay in one expression to be atomic` | `too strict` |
| `ADR-0002: ULIDs are 26 chars, the length check is intentional` | `fixing later` |
| `M13-06: the load harness genuinely spawns processes` | `TODO` |

## What a suppression is not for

- **Never** to get past a gate on a Story that has no time for the fix. Fix the
  code, or open the Story that will.
- **Never** file-wide or repository-wide. Silence the narrowest scope: one line,
  one rule.
- **Never** on a security check without a waiver. `bin/security` (M00-10) has its
  own waiver record with an owner and an expiry; an expired waiver blocks again.
  A `# nosec` is not a substitute for it.

## Changing a rule instead

If a rule is wrong often enough that people keep suppressing it, the rule is the
defect. Changing `.rubocop.yml`, `eslint.config.js` or a checker needs its own
Story or ADR and says so in the commit body — it is never a side effect of another
Story (Annex I §21.2). The Post-commit Gate flags a diff that touches a gate file
without that justification.
