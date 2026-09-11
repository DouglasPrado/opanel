# M01-92 — Test evidence that survives a commit, and two feedback gaps the loop has

## Objective
Stop the full suite from running three times per Story against an identical tree,
and close two places where the loop finds out too late about something it could
have said immediately.

## Outcome
A Story's suite runs once per change instead of once per gate stage. The gate that
reads a Story report says at the local stage that it cannot read it, instead of
after the commit. The independent reviewer starts from the list of mistakes this
pack has actually produced, rather than rediscovering them one Story at a time.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §11.1, §12.1 (*"a gate
  that is expensive gets bypassed, and a bypassed gate protects nothing"*), §21.2
  (a check moves, it is never removed)
- `docs/annexes/H-autonomous-development-loop.md` §4.1
- `docs/decisions/ADR-0004-in-process-milestone-loop.md`
- `lib/gates/post_commit.rb`, `lib/gates/acceptance_mapping.rb`, `bin/test`,
  `bin/gate`, `tools/opanel-loop/agents/`

## Preconditions
`M01-91`'s scope is adjacent but disjoint: that Story makes the gate cheaper by
scoping and parallelising, this one stops the same work from being repeated. They
may land in either order.

This Story edits `bin/gate*`, `bin/test`, `lib/gates/**` and the loop's own
agents, which no Story may touch from inside the work those gates judge — hence a
Story of its own, numbered outside the Milestone's range, and committed on its
own before any domain Story resumes (G02).

## The measurement this Story starts from

Per Story, on the reference machine, the **same suite against an identical tree**:

| Stage | Duration | What it runs |
|---|---|---|
| `bin/gate local` | ~578 s | the whole suite (487 s) + `gitleaks dir .` (81 s) |
| pre-commit hook | ~300–360 s | the whole suite again |
| `bin/test` after the commit | ~415–490 s | the whole suite a third time |

Roughly **22 minutes of identical re-execution per Story**, and none of the three
runs can see that the other two happened.

### Why the third run exists at all

`lib/gates/post_commit.rb` reads `tmp/test-results/rspec-metadata.json` and
compares its `commit` field against `HEAD`:

```
the test evidence is from commit 2af36ac3d, not from HEAD 4e38dd896 —
re-run the suite against what was committed
```

The pre-commit hook runs *before* the commit exists, so the evidence it produces
always names the parent. The suite therefore has to run a fourth time — after the
commit — purely to make the recorded hash match.

The check is right about what it wants and wrong about what it measures. The
question is *"did this suite run against this code?"*, and the commit hash is a
poor proxy for it in both directions: an empty commit invalidates evidence that is
still valid, and amending a commit message does too, while a commit that changes
only untracked files leaves it looking valid.

**Observed in `M01-06`:** the report was corrected, the change had to be amended
into the commit to keep the Story's deliverable in it, and the suite then ran
twice more — once for the amend's own pre-commit hook and once for the evidence.

## Scope

**1 — `bin/test` records the tree, not the commit.**

A content hash of the tracked working tree — `git ls-files -s` plus the hash of
each modified file, or `git stash create`'s tree, whichever proves simpler — goes
into `rspec-metadata.json` alongside what is there now. The commit hash stays,
because it is useful in a report; what changes is which field the gate compares.

**2 — every gate stage accepts evidence whose tree matches.**

`bin/gate local`, the pre-commit hook and `bin/gate post-commit` all ask the same
question and accept the same answer. A run made before the commit is valid after
it **when the tree is byte-identical**, which is exactly the case that costs two
extra runs today. A tree that differs by one character still invalidates it.

This is a strictly stronger check than the one it replaces, and the Story must
prove that: a spec plants a modified file after a green run and asserts the gate
refuses the stale evidence.

**3 — the acceptance mapping warns at the local gate.**

`acceptance-mapping` runs only in `post-commit`. A report whose Acceptance
Criteria section the checker cannot parse therefore surfaces after the commit —
and in this pack it surfaced **five Stories late**: the table format used since
`M01-05` put the criterion's prose in the first cell, where `TABLE_ROW` expects
the number alone, so every report mapped zero criteria and nobody saw it.

`bin/gate local` gains the same check as a **warning**: it does not block, it
prints which criteria the checker could not read, and it names the template. The
blocking version stays exactly where it is.

**4 — the reviewer starts from what this pack gets wrong.**

Every Story so far has produced findings from the same small set of shapes:

- a check that cannot fail — asserted on a value the code cannot produce, or on a
  copy of the logic under test;
- evidence in a report that names a file, a test or a constant that does not
  exist;
- a boundary widened during implementation and declared afterwards;
- an abstraction shipped ahead of its caller, untested;
- a claim in a report the repository contradicts.

`tools/opanel-loop/agents/reviewer.md` gains these as an explicit opening
checklist, with the instruction to attempt a mutation of the production code for
each assertion that carries an acceptance criterion. Both `M01-07` and `M01-08`
needed a second review round; the findings that forced them were all in this list.

## Out of Scope
- Removing, weakening or skipping any check. Every gate must fail on everything
  it fails on today, and `spec/gates/` proves that per check.
- `M01-91`'s scoping and parallelisation. Disjoint, and each is measurable alone.
- Changing what CI runs.
- The independent review's authority or verdict rules (ADR-0004). This changes
  what the reviewer is told to look for first, never who decides.

## Security Requirements
- The tree hash covers **tracked** files only, and a spec proves that a change to
  a tracked file invalidates evidence. An untracked file cannot make evidence
  look valid that is not, because an untracked file is not what was committed.
- The secret scan's scope is untouched here; it belongs to `M01-91`.

## Observability Requirements
- When evidence is rejected, the gate says *which* tree it expected and which it
  found, in the same shape it names a commit today.
- The local gate's acceptance warning names the criteria it could not read, never
  only that something is wrong.

## Failure Scenarios
| Scenario | Expected behaviour |
|---|---|
| A file changes after a green run | Every gate stage rejects the evidence, naming the tree. |
| A commit is amended with no content change | Evidence stays valid — the tree is identical, which is the whole point. |
| An empty commit is made | Evidence stays valid, and today it wrongly does not. |
| The metadata file is absent or unreadable | The gate fails closed, as it does today. |
| A report maps zero criteria | The local gate warns and continues; `post-commit` still blocks. |

## Acceptance Criteria
1. `bin/test` records a content hash of the tracked tree in
   `tmp/test-results/rspec-metadata.json`, alongside the commit hash it already
   records.
2. `bin/gate post-commit` accepts evidence whose tree hash matches `HEAD`'s tree,
   regardless of which commit produced it.
3. A change to any tracked file after a green run invalidates the evidence at
   every gate stage, proved by a spec that plants the change.
4. An amend that changes only the commit message keeps the evidence valid, proved
   by a spec.
5. A full Story — implement, gate, commit, post-commit — runs the suite **once**,
   proved by counting `rspec` invocations across the sequence.
6. `bin/gate local` reports, without blocking, any acceptance criterion the
   mapping checker cannot read, naming the criteria and the template.
7. `bin/gate post-commit` still blocks on an unreadable or unmapped criterion,
   with no change to its rules.
8. `tools/opanel-loop/agents/reviewer.md` names the five recurring finding shapes
   and requires a mutation attempt per acceptance-bearing assertion.
9. No check is removed from any gate, and every negative case in `spec/gates/`
   still fails the gate it targets.

## Required Tests
- **gates**: evidence accepted and rejected across the three stages, against a
  fixture repository; the amend case; the modified-file case.
- **integration**: one `rspec` invocation across a full Story sequence.
- **unit**: the tree hash is stable across two runs with no change, and differs
  after one.
- **documentation**: the reviewer agent names the five shapes (a text assertion
  is enough — what it is worth is judged by the next review, not by a spec).

## Quality Gates
Local Quality Gate; `spec/gates/` green; CI unchanged.

## Definition of Done
- [ ] The 9 Acceptance Criteria, with before/after timings per Story in the report.
- [ ] The suite runs once per Story instead of three times.
- [ ] Every negative case in `spec/gates/` still red where it should be red.
- [ ] Self-review with Critical = 0 and High = 0; `tasks.json` updated with the commit.
