---
name: review-milestone
description: Runs the independent review of a whole Opanel Milestone in a fresh read-only context, validates the verdict for coherence, writes MILESTONE_REVIEW_<NN>.md and records the result. Use when review-state is ready_for_review (e.g. "/review-milestone docs/implementation/M01").
---

# Independent Milestone review

You orchestrate the review. **You do not perform it** — a lead that reviews the
work it just led is not an independent reviewer, and the verdict would be worth
nothing.

Argument: the milestone directory. Below it is `<dir>`, `<Mxx>` its basename.

## 1. Open the review

```sh
tools/opanel-loop/scripts/review-state.sh <dir> review-start
NN=$(tools/opanel-loop/scripts/review-state.sh <dir> attempt-number)
```

`review-start` exits 2 and blocks the Milestone when the attempts are exhausted.
That is the correct end of an automated loop, not a problem to work around.

## 2. Dispatch the reviewer

Dispatch the `milestone-reviewer` agent in a **fresh context**, read-only. Give
it the milestone directory, the attempt number, `HEAD` and the branch — nothing
about how the work went, and none of your own opinion about it.

**When a previous round exists, the reviewer confirms before it explores.** Give
it the findings of `MILESTONE_REVIEW_<NN-1>.md` and ask it to report, first,
whether each one is closed — with the evidence — and only then to look for new
ones. Without that, every round re-reads the Milestone from scratch and finds a
different set, so nobody can tell convergence from churn. M00 ran six rounds and
its High count went 15 → 9 → 3 → 4 → 2 → 3; the two rises were new findings the
correction itself had introduced, and that only became visible in hindsight.

It executes `docs/goals/REVIEW_MILESTONE.md` and returns a markdown report plus
JSON matching `<repo>/scripts/schemas/codex-review.schema.json` — resolved from
the repository root. The plugin has its own `scripts/`, and a bare relative path
here sent the first reviewer looking in the wrong directory.

## 3. Validate before recording

The verdict is only worth what its coherence is worth. Check:

- each count equals the number of findings of that severity;
- `NOT_ACCEPTED` carries at least one Critical or High;
- `ACCEPTED` carries Critical = 0 and High = 0;
- every finding names a file and evidence you can locate.

If it does not hold:

```sh
tools/opanel-loop/scripts/review-state.sh <dir> error REVIEW_OUTPUT_INCONSISTENT
```

Run the reviewer **once** more. If the second result is also incoherent,
`review-state.sh <dir> block REVIEW_OUTPUT_INCONSISTENT` and stop. Do not repair
the reviewer's numbers yourself — correcting the verdict is writing it.

## 4. Record

Write `<dir>/MILESTONE_REVIEW_<NN>.md`, starting with:

```markdown
# Milestone Review <Mxx> — Attempt <NN>

- Reviewer role: Claude independent (read-only)
- Attempt: <NN>
- HEAD: <sha>
- Branch: <branch>
```

Then the reviewer's report verbatim, and its counts.

```sh
tools/opanel-loop/scripts/review-state.sh <dir> verdict <ACCEPTED|NOT_ACCEPTED> <c> <h> <m> <l>
git add -A && git commit   # docs(review): record MILESTONE_REVIEW_<NN> for <Mxx>
```

`ACCEPTED` moves the Milestone to `human_acceptance` and the run ends there.
**You never declare human acceptance**, and you never start the next Milestone —
only a person releases one.

`NOT_ACCEPTED` moves it to `fix_required`; the next turn is `/fix-milestone`.

## 5. Escalate when the loop is not converging

After recording a `NOT_ACCEPTED`, compare `Critical + High` with the previous
round. If it did **not fall** for two consecutive rounds, stop:

```sh
tools/opanel-loop/scripts/review-state.sh <dir> block NOT_CONVERGING
```

and say, in one message: both counts per round, which findings are new and which
are carried, and what a human has to decide. Do not start another fix round.

The budget is not the right place to discover this. M00 spent six rounds
reaching that conclusion, and the answer was available at round four — when High
went from 3 to 4 because the correction of round three had introduced its own
defects. Two rounds without progress means the loop is producing findings as fast
as it closes them, and no further automated round changes that.

Widening a budget to keep going is a human's call, recorded:

```sh
tools/opanel-loop/scripts/review-state.sh <dir> budget maxReviewAttempts <n> "<reason>"
```
