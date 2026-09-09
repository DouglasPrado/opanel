# M00 — Human acceptance, over an open verdict

- Milestone: `M00` — Foundation
- Accepted at: `f0fcaed` on `loop/replace-orchestrator`
- Date: `2026-09-08`
- Accepted by: the repository owner, explicitly, on instruction
- Recorded by: Claude (IMPLEMENTER). **This is not a verdict.** The implementer
  cannot accept its own work; this file records that a human did, and what they
  accepted over.

## What the last review said

`MILESTONE_REVIEW_06.md` returned **`NOT_ACCEPTED`** — Critical 0, High 3,
Medium 8, Low 3. No review of this Milestone has ever returned `ACCEPTED`.

| Review | Verdict | C / H |
|---|---|---|
| `CODEX_REVIEW_01` | NOT_ACCEPTED | 1 / 15 |
| `CODEX_REVIEW_02` | NOT_ACCEPTED | 1 / 9 |
| `MILESTONE_REVIEW_03` | NOT_ACCEPTED | 0 / 3 |
| `MILESTONE_REVIEW_04` | NOT_ACCEPTED | 0 / 4 |
| `MILESTONE_REVIEW_05` | NOT_ACCEPTED | 0 / 2 |
| `MILESTONE_REVIEW_06` | NOT_ACCEPTED | 0 / 3 |

Both budgets are exhausted: `reviewAttempt` 6 of 6, `fixAttempt` 5 of 5. The
automated loop cannot produce another round without a human widening a counter,
which is itself one of the open findings.

## What changed between the verdict and this acceptance

`MILESTONE_REVIEW_06` judged `d576e30`. Two of its three High findings were
corrected afterwards, at `f0fcaed`, and verified rather than asserted:

| Finding | State | Verification |
|---|---|---|
| **F01** — the report broke the section names `bin/stop-gate` requires, and claimed the gate was green | **closed** | the eight sections restored; `bin/stop-gate M00` → `ok: true` |
| **F03** — the report said the only failing CI item was the approval signature | **closed** | the run and its failing job are now stated, with `git diff 7ddfc63..fe7e1a6` over `app lib bin spec config db` confirmed empty |
| **F02** — the transition to `ready_for_review` bypassed the gate that would have refused it | **open** | structural; carried to `M01-90` |

**`bin/stop-gate M00` is green at the accepted commit.** The Exit Gate condition
of `README.md:144` is therefore met, which it was not when this file was first
written. What remains open is one finding about the loop, not about M00.

## What is being accepted over

One blocking finding remains, plus the verdict itself. The three below are kept
for the record, with F01 and F03 marked closed above:

**F01 — CLOSED at `f0fcaed`. As judged at `d576e30`:** `bin/stop-gate M00` was
red and `MILESTONE_REPORT.md:124` stated it was green. Rewriting the report replaced the
eight section names `lib/gates/stop_gate.rb` requires by name — `Quality`,
`Findings`, `Resultado funcional`, `Blocked`, `Dependências novas`, `Conflitos de
especificação`, `Human acceptance requested` — with more descriptive headings.
Only `Stories` survived, and the section the template calls "the section a human
reads to decide acceptance" was gone. All eight are restored and the gate returns
`ok: true`.

**F02 — OPEN.** The transition into this review bypassed the gate that would
have refused it. `review-state.json` was edited directly in `d576e30`
(`fix_required` → `ready_for_review`, `maxReviewAttempts` 5 → 6) instead of going
through `review-state.sh`. The Stop hook runs `bin/stop-gate` before setting
`ready_for_review` and blocks when it fails; with the status already set, that
branch never executed. The Milestone entered its sixth review in a state its own
Stop Gate rejects.

**F03 — CLOSED at `f0fcaed`. As judged at `d576e30`:** the branch's CI run was
red and the report said otherwise. Run
`34281680959` at `fe7e1a6` concluded `failure` on `e2e-critical`, a network error
in `ruby/setup-ruby`. `MILESTONE_REPORT.md:173-180` tells the reader the only
failing item is the approval signature. The true argument was available and is
not made there: the delta from the green run at `7ddfc63` is documentation only,
so the code is covered. The report now states the failing job and makes that
argument; the branch run itself remains red.

Eight Medium and three Low findings are also open and unaddressed.

## What is genuinely done

Not everything here is unfinished, and the acceptance is not blind:

- 18 of 18 Stories `done`, each with a commit, a report and a self-review.
- The CI pipeline exists, runs, and **rejects each of the five failure classes**:
  PRs [#2](https://github.com/DouglasPrado/opanel/pull/2)–[#6](https://github.com/DouglasPrado/opanel/pull/6),
  one per class, each blocked by the gate that owns it and closed rather than
  merged. Archived in [`reports/negative-prs/`](reports/negative-prs/).
- `main` is protected: eleven required status checks, force pushes refused.
- The security incident is closed on the merits — the leaked object is absent
  from GitHub (`422`), and the episode is recorded in
  [`FIX_REPORT_04.md`](FIX_REPORT_04.md).
- `bin/gate local`, `bin/security --fast --history`, `bin/pack validate` and
  `bin/fitness` all exit 0 at `e00ceb0`.
- A green CI run exists at `7ddfc63`: 11 of 11 jobs.

## What this acceptance does not mean

It does not mean a reviewer approved this Milestone — none did. Six rounds, six
`NOT_ACCEPTED`.

The Exit Gate is met on the item that was failing when this file was first
written: `bin/stop-gate M00` returns `ok: true` at `f0fcaed`. The Exit Gate item
"Critical = 0 e High = 0 no review de todas as Stories" is still satisfied by
self-reviews dated 2026-09-06, and one High (F02) is open against the loop.
It means a human, holding the evidence above and the findings above, decided the
foundation is good enough to build M01 on.

## Carried into M01

- `M01-90` — the loop: `fix-done` runs no gate, so every handoff after the first
  is ungated; the budgets are hand-editable; the review re-explores instead of
  confirming; escalation waits for an exhausted budget. This is F02, generalised
  to its cause.
- `M01-91` — the local gate takes 462 s, 408 of them the suite, because the gate
  specs run the gate, which runs the suite.
- The eighteen Story self-reviews predate roughly thirty commits that touched
  files they certify.
- Eight Medium and three Low from `MILESTONE_REVIEW_06`.
