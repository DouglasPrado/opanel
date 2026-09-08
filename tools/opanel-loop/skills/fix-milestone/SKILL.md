---
name: fix-milestone
description: Corrects the blocking findings of the most recent Milestone review, writes FIX_REPORT_<NN>.md and hands the Milestone back for review. Use when review-state is fix_required (e.g. "/fix-milestone docs/implementation/M01").
---

# Fix the blocking findings

You are the implementer in the correction phase of a reviewed Milestone. You are
not the reviewer and you cannot accept the Milestone.

Argument: the milestone directory — `<dir>` below, `<Mxx>` its basename.

## 1. Open the fix

```sh
tools/opanel-loop/scripts/review-state.sh <dir> fix-start
```

Exit 2 means the fix attempts are exhausted and the Milestone is blocked. That is
the designed end of the loop; a human decides what happens next.

`<NN>` is the number of the most recent `MILESTONE_REVIEW_<NN>.md` — or
`CODEX_REVIEW_<NN>.md` on a Milestone reviewed before this plugin.

## 2. Correct, following `docs/goals/FIX_REVIEW_FINDINGS.md`

Read `CLAUDE.md`, `docs/MASTER.md`, `docs/AGENT_RULES.md`, `<dir>/GOAL.md`, the
review, and **only** the Stories the blocking findings touch.

Dispatch the `builder` agent per affected Story. The rules that matter here:

- **Only `Critical` and `High`** from the most recent review. Record `Medium` and
  `Low`; fix one only when it is trivial, directly adjacent and already covered.
- Stay inside each Story's boundary in `boundaries.yml`. Widening one is a
  deliberate act that belongs in the report.
- Never change an acceptance criterion, a test, a gate or a rule to get green.
  That is the failure this whole loop exists to prevent.

## 3. Prove it

Run the affected tests, `bin/gate local`, and `bin/stop-gate <Mxx>`.

Write `<dir>/FIX_REPORT_<NN>.md`: each blocking finding with the evidence of its
correction, the files changed, the commands run **with their exit codes**, the
findings left open and why, and any conflict encountered.

Every number in that report is something the next reviewer will check. One that
does not survive checking discredits the whole document.

## 4. Hand back

Green:

```sh
git add -A && git commit    # fix(<scope>): answer MILESTONE_REVIEW_<NN>
tools/opanel-loop/scripts/review-state.sh <dir> fix-done
```

Not green, or a finding you cannot correct without breaking something else:

```sh
tools/opanel-loop/scripts/review-state.sh <dir> block "<reproducible reason>"
```

`fix-done` returns the Milestone to `ready_for_review` and clears the answered
verdict. You never write a verdict, never `accepted`, never `human_acceptance`.
