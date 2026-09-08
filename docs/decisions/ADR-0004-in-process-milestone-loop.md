---
title: "ADR-0004 — Milestone loop in-process, with a same-vendor independent reviewer"
status: "accepted"
date: "2026-09-08"
supersedes: "ADR-0003"
---

# ADR-0004 — Milestone loop in-process, with a same-vendor independent reviewer

## Context

`ADR-0003` put the independent Milestone review in a separate process running a
different vendor's CLI (Codex), reached through
`scripts/agent-orchestrator.sh` and its runners. The reasoning was sound and is
unchanged: **whoever implements must not be the one who approves.** Prompt-only
role separation is insufficient, because a reviewer with write access can fix
what it was supposed to report.

What did not survive contact was the process boundary.

Three review dispatches for M00 failed inside that CLI without ever producing a
verdict — twice on the account's usage limit, after 109,183 and 189,915 tokens.
Each failure needed a human to notice, and until `a14b632` each one also spent
one of the Milestone's three review attempts. The Milestone reached
`blocked` at 3/3 without any reviewer having formed an opinion about it.

Two further defects came from the same boundary. The runner discarded its CLI log
in a `trap`, so a block left no reproducible diagnosis — which Annex H forbids
everywhere, including here. And `REVIEW_MILESTONE.md` instructed the reviewer to
execute the suite and the gates from inside a sandbox that denies every write, so
the reviewer was told to do something it structurally could not do, at unbounded
cost.

## Decision

The Milestone loop runs **in-process**, in Claude Code, through the plugin
`tools/opanel-loop`. The independent Milestone reviewer is a Claude subagent.

Independence is preserved **structurally**, not by vendor:

- the reviewer runs in a **fresh context** that never saw the implementer's
  reasoning, on a **different model** from the builder;
- it is **read-only** by tool grant;
- it never writes the verdict. `scripts/review-state.sh` does, and it refuses
  `ACCEPTED` with any Critical or High finding and `NOT_ACCEPTED` with none;
- `scripts/tasks.sh` refuses `done` unless `review/<id>.md` exists and records
  Critical = 0 and High = 0;
- an accepted verdict reaches `human_acceptance`, never `done`. Only a human
  releases the next Milestone.

The attempt budgets stay. An execution failure is explicitly **not** a verdict
and does not spend one: it increments `executionFailures` instead.

## Consequences

**What improves.** No second vendor, account or credit line in the critical path.
The loop no longer depends on an external process that can die without a
diagnosis. Failures are visible in the same session that caused them.

**What we give up, and it is real.** The reviewer is now the same model family as
the implementer, so a blind spot shared by both is less likely to be caught than
it was under a different vendor. `ADR-0003` treated vendor diversity as part of
the independence; this ADR does not. The mitigation is the fresh context, the
different model, the read-only grant and the mechanical verdict — all of which
`ADR-0003` also had, minus the vendor.

That trade was made because a reviewer that cannot run is not more independent
than one that can. It should be revisited if a same-family review is ever
observed accepting a Milestone a different vendor would have rejected.

**Governance.** `CLAUDE.md` and `AGENTS.md` said Claude is never the independent
reviewer and must never write `reviewing`, `fix_required` or `human_acceptance`.
Under this ADR, a Claude subagent reviews and a script writes those states. Both
files are updated in the same change, so the normative instructions match the
machinery in use rather than contradicting it.

`ADR-0003` becomes `superseded`. The external runners stay in `scripts/legacy/`
so the Milestones reviewed under them remain readable; `CODEX_REVIEW_<NN>.md`
remains a valid historical artifact, and new reviews are `MILESTONE_REVIEW_<NN>.md`.

**What this ADR does not decide.** Whether `tools/**` and `.claude/**` belong in
`bin/merge-gate`'s `PIPELINE_PATHS` — today a change to the loop is invisible to
the pipeline-change check. That is a gate change and needs its own Story.

## Alternatives considered

**Keep Codex and buy credit.** Removes the immediate failure, not the class of
it: an external CLI can still die mid-review with the diagnosis discarded, and
the loop still stops until a human notices.

**Claude as fallback when Codex is unavailable.** Rejected while `ADR-0003`
stood, and rightly: a fallback that appears only under pressure is a fallback
nobody audits, and it would have made the independent review conditional on
billing. Making the same-vendor reviewer the *declared* arrangement, with its
trade written down, is honest in a way a silent fallback is not.

**Human review only.** Correct and unaffordable per Milestone. It remains the
final gate: `human_acceptance` is still where the automation stops.
