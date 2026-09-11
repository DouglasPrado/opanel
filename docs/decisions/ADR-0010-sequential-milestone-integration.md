# ADR-0010 — Each accepted Milestone merges to `main` before the next one starts

Date: 2026-09-11
Status: accepted on the owner's explicit instruction

Amends [`ADR-0007`](ADR-0007-autonomous-milestone-chain.md) §4, which decided
stacked branches and stacked Pull Requests.

## Problem

`ADR-0007` §4 stacked the Milestones: `milestone/m02` branches from
`milestone/m01`, its Pull Request targets that branch, and nothing merges to
`main` autonomously. The reasoning was that each PR then shows one Milestone's
diff, and the stack of open PRs is where the human enters.

That holds only if the human reads the stack. The owner has since decided
otherwise — they do not read the ADRs (which is why `adr-reviewer` exists) and
have not reviewed a Pull Request during the run. Under that, a stack does the
opposite of what it was chosen for:

- `main` is **148 commits behind** and has never received anything. No Pull
  Request has been opened at all.
- `M14` would sit on thirteen branches nobody read. The aggregate is
  unreviewable, which is the outcome stacking was meant to prevent.
- Nothing ever lands, so there is no integrated baseline anywhere — no point at
  which the suite, the gates and the fitness functions are known green together.

The stack was the right structure for a reviewer who reviews. It is the wrong one
for a run whose review happens elsewhere.

## Decision

**Milestones integrate sequentially through `main`.**

- `milestone/m<NN>` branches from `main`, not from the previous Milestone.
- Its Pull Request targets `main`.
- An accepted Milestone's PR is merged before the next Milestone starts, so each
  Milestone begins from an integrated, green baseline.
- `bin/next-milestone` does not release the next Milestone while the previous
  one's PR is open.

**What still does not happen autonomously.** The merge is a human action, and
`guard-bash.sh` keeps denying `git push` to `main` and `master`. The chain opens
the Pull Request and stops there; a person merges it. That is unchanged from
`ADR-0007` and is the last human checkpoint in this system.

**A Milestone does not open its PR with a red suite.** The failure baseline is
recorded per Milestone, and a Milestone that raises it hands the next one a
baseline nobody can tell from a regression — which this run's ledger has recorded
eight times, and which grew from six failures to fourteen in a single day.
Clearing what a Milestone broke is part of finishing it, not debt it may pass on.

## Alternatives rejected

**Keep the stack and ask the owner to review PR by PR.** The honest option, and
the one that keeps unreviewed code out of `main`. Rejected because it re-decides
a question the owner has already answered twice, and a design that depends on
behaviour its user has declined is a design that fails quietly.

**Merge automatically once the arbiter accepts.** Removes the last human
checkpoint and the `guard-bash` deny with it. Rejected: the cost of a bad merge
to `main` is borne by the owner, not the run, and the PR is cheap to merge when
they choose to.

**One long-lived integration branch, PR per Milestone against `main`.** Diffs
overlap — the `M05` PR would contain `M01`..`M04` — so every PR after the first
is unreviewable for a different reason.

## Consequences

Unreviewed code reaches `main` earlier, on a human's click rather than a human's
reading. That is the cost the owner has accepted, and it is the same trade
`ADR-0007` recorded; what changes is where it is paid.

In exchange there is an integrated baseline: after each merge, `main` is a point
where the whole suite, the gates and the fitness functions were green together,
and the next Milestone's first red is its own.

`ADR-0007` §4 is superseded. Its `Consequences` paragraph about the stack being
"reviewable in the order it was built" no longer describes the arrangement.

`M01` is the first Milestone under this: it merges to `main` when accepted, and
`M02` branches from `main` rather than from `milestone/m01`.
