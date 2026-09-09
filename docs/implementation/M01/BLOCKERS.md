---
title: "M01 — Blockers"
milestone: "M01"
type: "blockers"
---

# M01 — Blockers

Two blocks, both needing the same person: whoever may commit outside a loop run.
Neither is a Story that failed to converge — both are the loop refusing to let the
implementer touch the machinery that judges it, which is the rule working, not a
bug in the Story.

Per `docs/goals/G02-run-m01.md` the run stops here rather than starting a domain
Story: the Goal orders the gate change committed **on its own, before any domain
Story**, and that commit is exactly what is blocked.

---

## M01 — milestone-wide: `run-start` writes a key the pack contract rejects

- **Qualificador:** `BLOCKED_FOR_HUMAN_APPROVAL`
- **Data:** `2026-09-09`
- **Tentativas:** 1 (no second strategy exists that the implementer may take —
  see "Why this is a block")

### Diagnóstico reproduzível

```text
$ tools/opanel-loop/scripts/tasks.sh docs/implementation/M01 run-start
run started 2026-09-09T02:47:04Z

$ bin/pack validate
docs/implementation/M01/tasks.json
  SCHEMA             (root) carries the unknown property `run`
                     config/pack/tasks.schema.json is the contract, and this is it being applied

pack: FAIL (1 violation(s) in 15 milestone(s))
exit 1
```

Root cause, located in the commit that introduced it:

`9806315` (`feat(loop): gate the handoff…`, Story `M01-90`) added `cmd_run_start`
and `cmd_turns` to `tools/opanel-loop/scripts/tasks.sh`, which write a root-level
object:

```
tasks.sh:169   '.run = {startedAt: $now, turns: 0,
tasks.sh:170              doneAtStart: ([.stories[] | select(.status == "done")] | length)}'
tasks.sh:179   '.run.turns = ((.run.turns // 0) + 1)'
```

The same commit extended `config/pack/tasks.schema.json` — it added the per-Story
`review` and `reason` properties — but not a root-level `run`. The root object is
`"additionalProperties": false` with exactly five properties: `milestone`, `name`,
`status`, `dependencies`, `stories`.

`M00/tasks.json` has no `run` key, so nothing exercised this before: `run-start`
is called once, at the start of a run, and this is the first run since `9806315`.

### Why this is a block and not a bug to fix

The two ways to fix it are both closed to the implementer:

1. **Change `tools/opanel-loop/scripts/tasks.sh`.** `CLAUDE.md` §Fixed Role
   forbids modifying the loop — "its scripts, schemas, hooks, agents or skills" —
   while executing a Milestone. Outside a run, on human instruction, it is
   ordinary work in its own commit.
2. **Add `run` to `config/pack/tasks.schema.json`.** That is the pack contract a
   gate enforces. Widening a contract so a red check goes green is what
   `AGENT_RULES` §Quality Gates forbids without its own Story or ADR — and here
   the red check is telling the truth.

Deleting `.run` from `tasks.json` is not a third option: the Stop hook calls
`tasks.sh turns increment` on **every** turn (`stop-gate.sh:47`), and
`.run.turns = ((.run.turns // 0) + 1)` recreates the key. The violation returns at
the end of whatever turn removed it.

### Blast radius

- `GOAL.md` completion condition 4 — `bin/pack validate` exit 0 — cannot be met
  while a run is active.
- `spec/gates/pack_spec.rb` ("validates every Milestone of this repository") is
  red, which makes the `tests` check of `bin/gate local` red for **any** Story on
  this branch. `main` is at `219e16c` and holds only a README, so `bin/test
  --changed` resolves against a merge base of the initial commit and selects
  essentially the whole suite — `pack_spec.rb` included, for every Story.
- Therefore no Story can be closed with a green local gate, and
  `bin/stop-gate M01` cannot reach `ok`.

### O que destravaria

- One decision, by the repository owner, in its own commit outside this run:
  either add a `run` object to `config/pack/tasks.schema.json`, or move the
  loop's run state out of `tasks.json` into a file the pack contract does not
  govern (e.g. `review-state.json`, which already holds run-scoped state such as
  `reviewAttempt` and the budgets).
- The second is the better shape — `tasks.json` is the Implementation Pack's
  durable record and `run` is per-run bookkeeping — but it is a contract change
  either way, so it is the owner's call, not the implementer's.

### Trabalho independente que continuou

None, deliberately. `G02` requires the gate/loop change to be committed alone
before any domain Story, and both available gate commits are blocked. Starting
`M01-01` ahead of them would violate the Goal's stated order and would close
Stories against a gate that is red for a reason unrelated to them.

---

## M01-91 — Bring the local gate back inside its budget

- **Qualificador:** `BLOCKED_FOR_HUMAN_APPROVAL`
- **Data:** `2026-09-09`
- **Tentativas:** 2

### Diagnóstico reproduzível

The Story's remaining scope is two lines in `bin/gate`'s `local` case. Every
attempt to edit that file is refused by the loop's own PreToolUse guard:

```text
$ echo '{"tool_input":{"file_path":"'"$PWD"'/bin/gate"}}' \
    | CLAUDE_PROJECT_DIR="$PWD" tools/opanel-loop/hooks/scripts/guard-edit.sh
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
 "permissionDecisionReason":"This is a quality gate. Failing a gate means fixing
 the implementation — a gate edited to pass protects nothing."}}
```

The builder attempted the edit twice through the `Edit` tool and received that
message verbatim both times. `guard-edit.sh:40` matches
`^bin/(gate|stop-gate|merge-gate)` and denies unconditionally — it has no notion
of a Story, so it cannot distinguish the Story that **declares** `bin/gate` in
`boundaries.yml` from any other Story trying to edit its way past a red check.

### Why this is a block and not a bug to fix

`docs/goals/G02-run-m01.md` authorises this Story by name to edit `bin/gate`, and
`M01-91` declares it in `docs/implementation/M01/boundaries.yml`. The guard is
nonetheless correct to be unconditional today, and the instruction was explicit:
do not look for a way around it. No workaround was attempted — no `Write`, no
`sed`/`perl` rewrite, no hook edit, no `--no-verify`, no sandbox override.

This is the same reason the first half of this Story was delivered
**interactively** by the repository owner, in `70c7f7e` and `3d05b73`, rather
than by the loop. The Story file records that; it did not record that the second
half has the same obstacle.

### What was delivered anyway

The defect the Story exists to fix — the suite not being parallel-safe — is
fixed and evidenced, inside the declared boundary. The root cause was not the one
the Story's text predicted: the five red examples are not four logging examples
plus a scan, they are two shared-working-tree races. See
`reports/M01-91.md` for the reproduction, the fix
(`spec/support/repository_lock.rb`), and the repeated `--parallel` runs.

Blocked criteria: **AC1** (under 90 s) and **AC5** (`bin/gate local` runs
`bin/test --changed --parallel`), plus the `local`-specific half of Scope item 3
(diff-scoping the secret scan).

### What the independent review found — `review/M01-91.md`, `COUNTS 1 2 2 0`

`Critical = 1`, `High = 2`. The Story cannot be `done`, and one of those findings
is the reason this block is not merely about a denied edit.

- **F-1, Critical — AC1 is not reachable even once the edit is unblocked.** The
  reviewer reproduced the timing independently, twice: `bin/test --parallel` over
  the five affected files finished in **145.4 s** and **142.9 s** (169 examples,
  0 failures both runs). The Story's own "Já entregue" section projected 88 s,
  measured *before* the five collisions were root-caused. With the mutual
  exclusion correctness now requires, `security_scan_spec.rb`'s ~85 s whole-tree
  scan sits on the critical path and can no longer overlap a planted probe — so
  the `tests` check alone exceeds the 90 s **total** gate budget before
  `format`/`lint`/`typecheck`/`security` add their ~11 s. **The 90 s ceiling is a
  property of the Story that the measurement has disproved**, not something the
  implementation failed to reach.
- **F-2, High — the AC7 budget spec asserts only against synthetic hashes**, so it
  cannot fail on a real regression; today's actual state (`--parallel` missing
  from `bin/gate`) produces no red anywhere. This is *also* waiting on the same
  human decision as F-1: a spec that asserts the live gate "under its ceiling"
  cannot be written until the ceiling has a defensible number.
- **F-3, High — the Required Test "one rspec process per gate run" has no
  automated check**, only a one-off `ps aux` observation. This one is independent
  of the ceiling and is straightforwardly fixable.
- **F-4, Medium** — the report marks AC1 `[x]` while its own sentence says "Not
  met; blocked". Left uncorrected deliberately: the implementer's report is its
  own artifact, and the review already records the contradiction.
- **F-5, Medium** — the single global `flock` is correct today (verified twice,
  no deadlock path) but is now the serialization bottleneck working against the
  Story's own goal.

What held: the `RepositoryLock` fix is sound, no assertion in any touched spec was
weakened, narrowed, skipped or removed (the reviewer compared every diff hunk —
strictly wrap-in-lock), and nothing fell outside the declared boundary.

### Why no third attempt was spent

Attempt 2 of 3. A third builder run could close F-3 and F-4, but not F-1 or F-2 —
both wait on the same decision only the owner can make, and that decision may
change the ceiling F-2's spec is supposed to assert. Building a live-budget
assertion against a number that is about to move is work thrown away. The Story
stops here with `Critical = 1` and a diagnosis, rather than converging on
appearance.

### The work is uncommitted, and deliberately so

`git status` is dirty. These files carry the parallel-safety fix and are **not**
committed:

```text
 M spec/gates/ci_pipeline_spec.rb
 M spec/gates/gate_scripts_spec.rb
 M spec/security/production_logging_spec.rb
 M spec/security/security_scan_spec.rb
?? spec/support/repository_lock.rb
?? spec/gates/gate_budget_spec.rb
?? docs/implementation/M01/boundaries.yml
?? docs/implementation/M01/reports/M01-91.md
```

Two reasons, both of them rules rather than caution:

1. `tasks.sh set M01-91 done` is refused with `Critical = 1`, and the commit step
   of the loop follows `done`. A Story with an open Critical finding is not a
   checkpoint.
2. `bin/gate pre-commit` cannot be green. It runs `bin/test --changed --fast`;
   `gate_files` (`bin/_gate_lib.sh:286`) resolves `changed` against
   `git merge-base HEAD main`, `main` is `219e16c` — a README — so the changed set
   is effectively the whole repository, `spec/gates/pack_spec.rb` included, and
   that spec is red for the milestone-wide reason above. `pack_spec.rb` is not
   tagged `:slow`, so `--fast` does not drop it.

`OPANEL_GATE_BASE` would narrow the gate's base commit and make it green. That is
narrowing a gate to pass it, so it was not used.

Nothing here is lost — the tree is intact and the diff is reviewed. It needs a
commit by someone who may make one over a gate that is red for a cause outside
the Story, or the milestone-wide block cleared first, which makes the gate green
on its own.

### O que destravaria

- The repository owner applies the two-line change in `bin/gate`'s `local` case
  interactively — `bin/test --changed` → `bin/test --changed --parallel`, and the
  adjoining comment, which currently says the parallel-safety fix is still owed;
- **or** teaches `guard-edit.sh` to allow a path a Story declares in its
  `boundaries.yml` (a loop change, its own commit, outside a run — and a change
  that weakens a deliberate guard, so it deserves the thought an ADR gives it);
- **and** decides what to do about AC1's 90 s ceiling given the measurement
  above: relax it with a reason, or accept a follow-up Story for the deeper fix
  (scan a git worktree snapshot instead of the live checkout, which removes the
  need for mutual exclusion).
