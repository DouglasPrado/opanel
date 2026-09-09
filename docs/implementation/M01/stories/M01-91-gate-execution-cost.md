# M01-91 — Bring the local gate back inside its budget

## Objective
Cut `bin/gate local` from 462 s to under 90 s without removing a single check, by
fixing the recursion that makes the suite run itself and by using the scoping
knobs `bin/test` already has.

## Outcome
A Story's author runs the local gate as a matter of course instead of deciding
whether it is worth the wait. The checks that run are the same ones; what changes
is that running them costs a minute rather than eight.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §11.1 (Local Quality
  Gate), §12.1 ("a gate that is expensive gets bypassed, and a bypassed gate
  protects nothing"), §21.2 (a check moves, it is never removed)
- `docs/annexes/D-test-strategy.md` §20, §21
- `bin/gate`, `bin/test`, `spec/spec_helper.rb`, `spec/gates/gate_scripts_spec.rb`

## Preconditions
M00 accepted. This Story edits `bin/gate*` and `spec/gates/`, which no Story may
touch from inside the work those gates judge — hence a Story of its own, and the
reason it is numbered outside the Milestone's own range rather than folded into it.

## The measurement this Story starts from

`bin/gate local` at `e00ceb0`, on the reference machine:

| Check | Time |
|---|---|
| `tests` | **408 606 ms** |
| `security` | 41 300 ms |
| `lint` | 3 523 ms |
| `frontend-tests` | 3 132 ms |
| `typecheck` | 2 179 ms |
| `format` | 2 090 ms |
| `contracts` | 382 ms |
| `fitness` | 167 ms |
| `migrations` | 67 ms |
| **total** | **462 023 ms** |

Everything that is not `tests` or `security` sums to 11 s. The problem is two
checks, and one of them dominates.

### Why `tests` costs 408 s

`spec/gates/gate_scripts_spec.rb` makes **27** `Open3.capture2e` calls to gate
binaries — `bin/gate`, `bin/format`, `bin/lint`, `bin/typecheck`, `bin/security`,
`bin/migration-gate`, `bin/pack`, `bin/stop-gate`. One of them is `bin/gate`
itself, which runs `bin/test`, which runs the suite again.

Two `rspec` processes are visible during a run, and the outer one accumulates
~2 s of CPU over six minutes of wall clock: it is not computing, it is waiting
for the copy of itself that it started.

The intent is sound — the only way to prove a gate can fail is to run it against
a planted failure. What is wrong is the target: it runs against **this**
repository, so proving the gate costs a full suite.

### Why the knobs already there are not used

`bin/test` accepts `--fast` (drops `:slow`, the tag that marks exactly these
re-entrant suites) and `--parallel` (one database per worker). `bin/gate
pre-commit` uses the fast path and says why in a comment. **`bin/gate local` uses
neither** — it calls `bin/test --changed` and nothing else.

## Scope

**1 — Prove the gates against a fixture repository, not this one.**
`spec/gates/gate_scripts_spec.rb` and `spec/gates/ci_pipeline_spec.rb` build a
minimal repository in `tmp/` — a couple of files, a git init, the gate scripts —
and run the gate against that. The negative cases stay: a planted lint offence, a
staged secret, a failing spec, an invalid migration. What disappears is the
suite re-entering itself.

**2 — `bin/gate local` runs `bin/test --changed --parallel`.** The `:slow`
suites stay in `local` — after step 1 they are cheap — and CI keeps running
everything. No check is removed, and `--fast` is deliberately **not** adopted for
`local`: dropping the gate suites from the gate a Story author runs is how a gate
stops being exercised.

**3 — Scope the secret scan by gate.** `local` scans the diff, `pre-commit`
already uses `--staged`, and the full `gitleaks dir .` plus the history scan
belong to CI and to `post-commit`. A secret in the diff is what a local gate can
act on; a secret in history is a repository-wide fact that a per-Story gate
re-discovers 41 s at a time.

**4 — A regression test on the budget itself.** A spec asserts `bin/gate local`
completes under a declared ceiling on the reference dataset, so this cannot
silently regress. The ceiling is a number in one place, with the reason next to
it.

## Out of Scope
- Removing, weakening or skipping any check. The gate must fail on everything it
  fails on today; `spec/gates/` proves that per check.
- Changing what CI runs. CI keeps the full suite, the full scan and the history
  scan.
- The `:slow` policy in `spec_helper.rb`. After step 1 the tag covers far less,
  but the rule — "nothing else may be tagged `:slow`; a slow test that is merely
  slow is a test to fix" — stands.
- `bin/gate post-commit`, which runs once per Story and is not the bottleneck.

## Security Requirements
- The secret scan is **not** weakened. Its scope per gate becomes explicit, and
  the full tree-and-history scan remains mandatory in CI and `post-commit`.
- The fixture repository never holds a real credential; planted material is
  synthetic and lives under `tmp/`, which `.gitignore` and the gitleaks allowlist
  already cover.
- `bin/security --staged` must keep rejecting a staged secret. That negative test
  is the one that matters most here and is proved against the fixture.

## Observability Requirements
- `bin/gate` already reports per-check duration; the Story's report records the
  before and after for each.
- The budget spec names the check that exceeded the ceiling, not just the total.

## Failure Scenarios
| Scenario | Expected behaviour |
|---|---|
| A gate stops catching a class it caught before | The negative test for that class fails. This is the Story's own tripwire. |
| The fixture diverges from the real repository | The fixture is built by the same scripts under test; a divergence that matters shows up as a gate that passes on the fixture and fails here. |
| The budget spec is red on a slower machine | The ceiling is declared per environment, not as a wall-clock constant tuned to one laptop. |
| A future Story re-introduces recursion | The budget spec goes red, with the check named. |

## Acceptance Criteria
1. `bin/gate local` completes in **under 90 s** on the reference dataset, from 462 s.
2. No check is removed from any gate; `bin/gate local`, `pre-commit` and
   `post-commit` run the same named checks as before.
3. Every negative case in `spec/gates/` still fails the gate it targets — lint,
   typecheck, test, staged secret, invalid migration, boundary violation, stray
   file, missing evidence.
4. The suite no longer re-enters itself: a run of `bin/gate local` starts exactly
   one `rspec` process.
5. `bin/gate local` runs `bin/test --changed --parallel`, and the `:slow` suites
   are included rather than skipped.
6. The secret scan's scope per gate is explicit and documented in `bin/security`;
   the full tree-and-history scan still runs in CI and in `post-commit`.
7. A spec asserts the local-gate budget and names the offending check when it is
   exceeded.
8. CI runs exactly what it ran before, and its duration does not increase.

## Required Tests
- **gates**: every existing negative case in `spec/gates/`, re-pointed at the
  fixture repository and still failing what it targeted.
- **security**: `bin/security --staged` rejects a staged secret; the history scan
  still rejects a secret reachable from `HEAD`.
- **budget**: the local gate under its ceiling; the ceiling exceeded produces a
  named check.
- **integration**: one `rspec` process per gate run.

## Quality Gates
Local Quality Gate; the Story's own budget spec; CI unchanged and green.

## Definition of Done
- [ ] The 8 Acceptance Criteria, with before/after timings per check in the report.
- [ ] `bin/gate local` under 90 s, no check removed.
- [ ] Every negative case in `spec/gates/` still red where it should be red.
- [ ] Self-review with Critical = 0 and High = 0; `tasks.json` updated with the commit.
