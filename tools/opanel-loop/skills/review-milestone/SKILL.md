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

It executes `docs/goals/REVIEW_MILESTONE.md` and returns a markdown report plus
JSON matching `scripts/schemas/codex-review.schema.json`.

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
