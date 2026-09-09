# M01-90 — Make the loop converge, or stop and say why

## Objective
Close the four holes that let M00 spend two days and six review rounds on
findings the machine could have caught itself, and that let the implementer hand
work back in a state its own Stop Gate rejects.

## Outcome
A Milestone either converges in two or three rounds or stops and asks a human,
with the reason. What reaches the reviewer has already passed the mechanical
checks, so the reviewer spends its attention on judgement rather than on running
`bin/stop-gate` for the first time.

## References
- `docs/annexes/H-autonomous-development-loop.md` §4.2 (Stop Gates), §6.2 (attempt policy)
- `docs/decisions/ADR-0004-in-process-milestone-loop.md`
- `docs/implementation/M00/MILESTONE_REVIEW_06.md` — F01, F02
- `tools/opanel-loop/scripts/review-state.sh`, `tools/opanel-loop/hooks/scripts/stop-gate.sh`

## Preconditions
M00 handed over. This Story edits the loop itself, which no Milestone may touch
while the loop is executing it — hence a Story of its own, before the Milestone's own Stories.

## What M00 measured

Six reviews. Verdict `NOT_ACCEPTED` every time. Critical 1→1→0→0→0→0, High
15→9→3→4→2→3.

The High count rose twice — at rounds 04 and 06 — and both times the new findings
were produced by the implementer while correcting the previous round. Round 06's
three were: a report whose section names broke `bin/stop-gate`; a state
transition written by hand that bypassed the gate; and a false claim that CI was
green.

**Two of those three were mechanically detectable before the reviewer ever
started.** `bin/stop-gate M00` and `gh pr checks` would have caught F01 and F03
in seconds.

## The hole

`bin/stop-gate` runs in exactly one place: `hooks/scripts/stop-gate.sh:110`, in
the `implementing` branch, when the last Story closes.

`review-state.sh cmd_fix_done` sets `ready_for_review` and verifies **nothing**.

So the first handoff of a Milestone is gated and **every subsequent one is not**.
After round one, the reviewer becomes the first thing to execute the checks — the
most expensive component in the system doing the cheapest work in it.

## Scope

**1 — `fix-done` runs the Stop Gate and refuses a red result.**

```
fix-done → bin/stop-gate <Mxx>
  ok:true   → ready_for_review
  ok:false  → exit 2, state stays `fixing`, the failing checks are named
```

One gate run per fix round. It would have stopped round 06 from existing.

**2 — The state file stops being hand-editable.**

- `review-state.sh budget <field> <value> <reason>` — the only way to change
  `maxReviewAttempts` or `maxFixAttempts`, and it records the reason in the file.
  Today the script writes them once in `init` and offers no command, so three
  raises during M00 were hand edits.
- `set` no longer accepts `ready_for_review`. Only `fix-done` and the Stop hook
  reach it, and both pass through the gate.

**3 — The review confirms before it explores.**

`/review-milestone` instructs the reviewer to **first** verify whether each
finding of the previous round is closed, and report that as a list, **then** look
for new ones. Convergence becomes visible: "2 closed, 3 new" is data, not a
surprise. Today every round re-reads the whole Milestone from scratch and finds
different things.

**4 — Early escalation.**

Two consecutive rounds without a fall in Critical + High → the loop stops and
asks a human, with both counts and the diff between the findings. Today it stops
only when a budget runs out, which is how M00 spent six rounds discovering it
needed a human at round two.

## Out of Scope
- Changing what a review judges, or the `ACCEPTED` bar. `Critical = 0` and
  `High = 0` stand.
- The budgets' default values.
- `M01-00`'s subject — the 462 s local gate. Related, separate.

## Security Requirements
- `budget` must not become a way to grant unlimited rounds: it records who asked
  and why, and the reason is part of the state a reviewer reads.
- Blocking `set ready_for_review` must not create a path that skips the gate by
  another name. The gate call belongs in the script, not in the caller.

## Observability Requirements
- A refused `fix-done` names the failing checks, not just "not ok".
- The escalation message carries both counts, the round number and which findings
  are new versus carried.

## Failure Scenarios
| Scenario | Expected behaviour |
|---|---|
| `bin/stop-gate` is red at `fix-done` | Refused, exit 2, state stays `fixing`, checks named. |
| `bin/stop-gate` cannot run at all | Treated as red. A gate that did not run is not a gate that passed. |
| Someone edits `review-state.json` by hand anyway | Out of the script's reach — but the next `fix-done` runs the gate, so the state cannot stay wrong silently. |
| Two rounds without convergence | The loop stops with the counts, rather than consuming the budget. |
| The budget is raised without a reason | Refused. |

## Acceptance Criteria
1. `fix-done` runs `bin/stop-gate` and refuses `ready_for_review` when it is not
   `ok`, leaving the state at `fixing` and naming the failing checks.
2. A Stop Gate that fails to execute is treated as failing.
3. `review-state.sh budget <field> <value> <reason>` exists, is the only way to
   change either maximum, and records the reason in the state file.
4. `set` refuses `ready_for_review`.
5. `/review-milestone` reports, before any new finding, whether each finding of
   the previous round is closed.
6. Two consecutive rounds without a fall in Critical + High stop the loop and
   name what a human must decide.
7. `smoke-test.sh` covers each of the above, including the refusals.
8. Replaying M00's round 06 against the new `fix-done` refuses the handoff.

## Required Tests
- **smoke**: `fix-done` refused on a red gate; refused when the gate cannot run;
  `set ready_for_review` refused; `budget` without a reason refused.
- **integration**: a fixture Milestone with a deliberately broken
  `MILESTONE_REPORT.md` cannot reach `ready_for_review`.
- **regression**: criterion 8, against the real M00 state at `d576e30`.

## Quality Gates
Local Quality Gate; `tools/opanel-loop/scripts/smoke-test.sh` green.

## Definition of Done
- [ ] The 8 Acceptance Criteria, with the refusals demonstrated rather than described.
- [ ] `smoke-test.sh` green, with the new cases.
- [ ] Self-review with Critical = 0 and High = 0; `tasks.json` updated with the commit.
