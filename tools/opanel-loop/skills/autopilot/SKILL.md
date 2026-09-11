---
name: autopilot
description: Runs the whole Milestone chain unattended — picks the next eligible Milestone, runs its Stories through /backlog, arbitrates every decision that used to stop for a human, opens a stacked Pull Request, and moves to the next Milestone. Use when the user asks to run everything, run the roadmap, or continue the autonomous chain.
---

# Autopilot

You run the **chain**, not a Story and not a Milestone. `/backlog` is one
Milestone; this is every Milestone, one after another, without stopping for a
person. The decision to work this way is `ADR-0007`; read it before your first
arbitration.

Takes no argument. The chain decides where it is from what is recorded.

## The cycle

```text
bin/next-milestone
      │
      ▼
  branch (stacked)  ──▶  /backlog <dir>  ──▶  /review-milestone  ──▶  arbitrate
      ▲                                                                   │
      │                                                                   ▼
      └────────────────  bin/milestone-pr <Mxx>  ◀──────────────────  accepted
```

**1 — Pick.** `bin/next-milestone`. Exit 1 means the chain is finished — say so
and stop. Exit 3 means the arbiter blocked a Milestone the rest of the stack sits
on; report it and stop, because nothing downstream can be built on it.

**2 — Stack the branch.** `M01` sits on `main`; `M<NN>` sits on `M<NN-1>`.

```sh
git checkout milestone/m<NN-1>            # or main, for M01
git checkout -B milestone/m<NN>
```

Never branch a Milestone from `main` when an earlier Milestone is still an open
Pull Request — it would silently drop that Milestone's work out from under this
one.

**3 — Run it.** `/backlog docs/implementation/M<NN>`. The Stop hook drives every
turn from there; follow exactly what it names and do not improvise order.

**4 — Arbitrate whenever the hook says so.** See below.

**5 — Ship and continue.** When the state reaches `accepted`, run
`bin/milestone-pr M<NN>`, then start the cycle again. Do **not** merge the Pull
Request, and do not wait for it.

## Arbitration

Whenever the Stop hook tells you to dispatch the arbiter, dispatch the `arbiter`
agent in a **fresh context** — it must not see the reasoning of the builder,
reviewer or lead that produced the situation. Give it exactly three things:

- the situation the hook named, in the hook's words;
- the paths to the evidence (the review file, the gate output, the Story, the
  recorded `blockedReason`);
- nothing else. No summary of what you think it should decide.

It returns one decision block. **Append it verbatim** to
`docs/implementation/M<NN>/DECISIONS.md`, creating the file if it does not exist,
then act on the verdict:

| Verdict | What you do |
|---|---|
| `FIX` | One bounded round on exactly the change the arbiter named. Then proceed whatever the outcome — do not open a second round on the same finding. |
| `DEBT` | Record it and carry on. The debt reaches the Pull Request through `bin/milestone-pr`. If it names an inheriting Milestone, add the Story to that Milestone's `tasks.json`. |
| `BLOCK` | `review-state.sh <dir> arbitrate` writes the block. Where it stops depends on `Blocks-On` — see below. |

A `BLOCK` is two different stops, and the arbiter's `Blocks-On` line says which:

- **`Blocks-On: HUMAN`** — the chain ends. Nothing an agent may decide.
- **`Blocks-On: ADR`** — the work is blocked on a decision nobody has written
  down, which is work an agent can do. Dispatch the `adr-author` agent in a fresh
  context with the arbiter's ledger entry and the evidence it cites. Write what it
  returns to `docs/decisions/ADR-<NNNN>-<slug>.md` with the next free number, then:

  ```sh
  tools/opanel-loop/scripts/review-state.sh <dir> adr-written docs/decisions/<file>
  ```

  That refuses a path that is not on disk, so the block cannot be lifted by
  asserting a decision was made. The Milestone returns to `implementing` and the
  Story that needed the decision is reopened.

  Two other answers come back from `adr-author` and neither is a failure:
  `ALREADY DECIDED` means an approved document settles it and the implementation
  disagrees — record it in `DECISIONS.md`, fix the code, write no ADR.
  `NEEDS HUMAN` means it refused; treat it as `Blocks-On: HUMAN` and stop.

  You do not write the ADR yourself, and you do not implement against a decision
  in the same context that made it.

You do not argue with the arbiter, you do not re-dispatch it hoping for a
different verdict, and you do not decide any of this yourself. An arbitration you
performed in your own context is not an arbitration — it is the implementer
approving its own work, which is the one thing this whole design exists to
prevent.

## Rules that do not bend

- **Never merge to `main`.** Not the stack, not a single PR, not "to unblock the
  next Milestone". The open stack is the only place a human still enters.
- **Never edit a gate, threshold, assertion or boundary to get green.** `ADR-0007`
  changed what a red gate *does*; it did not make gates optional.
- The `guard-bash.sh` **deny** list stands. No production deploy, no destructive
  database operation, no force push, no production credential — the arbiter may
  not authorise any of them and neither may you.
- **A Critical still blocks a Story.** `tasks.sh set <ID> done` refuses it, and
  that refusal is correct.
- **Without evidence there is no success.** Commands, exit codes, and the
  acceptance criteria they satisfy. A chain that runs unattended is worth exactly
  what its records are worth.

## When the session ends

It will — context runs out, the turn budget trips, the machine sleeps. That is
expected and is why `bin/autopilot` exists: it starts a fresh session and this
skill rebuilds state from the repository. Never carry state across sessions in
your head, and never resume from a conversation summary. `bin/next-milestone`,
`review-state.json` and `tasks.json` are the truth.
