# Milestone Report — M00 Foundation

Status: READY_FOR_REVIEW

- Milestone: `M00` — Foundation
- Branch: `loop/replace-orchestrator`
- Head: `fe7e1a6`
- Repository: `DouglasPrado/opanel` — **public**, recreated on `2026-09-08` (see
  "The security incident")
- Date: `2026-09-08`
- Implementer: Claude (IMPLEMENTER role — this is **not** an independent review
  and carries no verdict)

M00 builds no Opanel domain entity. It builds the machinery every later Milestone
is judged by: the runtime, the harnesses, the gates, and the loop's own memory.

## Review history

Five independent reviews. This report is written **after** all of them and
describes the state at `fe7e1a6`, not the first pass.

| Review | Against | Verdict | Answered by |
|---|---|---|---|
| `CODEX_REVIEW_01.md` | `2a38d11` | NOT_ACCEPTED — C1 H15 | [`FIX_REPORT_01.md`](FIX_REPORT_01.md) |
| `CODEX_REVIEW_02.md` | `4b357cf` | NOT_ACCEPTED — C1 H9 | [`FIX_REPORT_02.md`](FIX_REPORT_02.md) |
| `MILESTONE_REVIEW_03.md` | `b9aa412` | NOT_ACCEPTED — C0 H3 | [`FIX_REPORT_03.md`](FIX_REPORT_03.md) |
| `MILESTONE_REVIEW_04.md` | `31a2cae` | NOT_ACCEPTED — C0 H4 | [`FIX_REPORT_04.md`](FIX_REPORT_04.md) |
| `MILESTONE_REVIEW_05.md` | `03435fb` | NOT_ACCEPTED — C0 H2 | this report |

Three further dispatches produced no verdict at all: the external reviewer's CLI
stopped on its account usage limit, twice after burning six figures of tokens.
That is why `a14b632` separated an execution failure from a verdict, and
ultimately why `ADR-0004` moved the loop in-process.

The trajectory is the honest summary of this Milestone: Critical 1 → 1 → 0 → 0 →
0; High 15 → 9 → 3 → 4 → 2. The one increase, review 04, was damage caused by the
correction of review 03 — recorded under "The security incident".

## Stories

18 required, 18 `done`, 0 blocked. Every commit hash below is in this branch's
history.

| Story | Title | Commit |
|---|---|---|
| M00-01 | Repository layout and Rails 8.1 application skeleton | `d85418b` |
| M00-02 | PostgreSQL, database bootstrap and migration tooling | `86163d7` |
| M00-03 | Solid Queue and asynchronous job baseline | `2d1d290` |
| M00-04 | Inertia + React + TypeScript + Vite + Tailwind integration | `7241a05` |
| M00-05 | Import and inventory the existing React component library | `a999b21` |
| M00-06 | Reproducible local development environment | `b8a5f82` |
| M00-07 | Backend test harness with real PostgreSQL | `d10e688` |
| M00-08 | Frontend component tests and browser E2E harness | `97eabb3` |
| M00-09 | Lint, format and typecheck toolchain | `202c052` |
| M00-10 | Security scanning baseline | `e12d5c8` |
| M00-11 | CI pipeline with PR and Merge gates | `e256b12` |
| M00-12 | Local, pre-commit and post-commit gate scripts | `65c3f0f` |
| M00-13 | Architecture fitness functions AF-01..AF-10 | `0214fb4` |
| M00-14 | Autonomous Development Loop scaffolding | `11c9a16` |
| M00-15 | Structured logging, correlation IDs and health endpoints | `524e9ed` |
| M00-16 | Environment configuration and development secrets management | `4070dab` |
| M00-17 | Disposable Docker/Swarm Lab harness | `f230511` |
| M00-18 | ADR, Story Report and Milestone Report templates | `319aa15` |

The titles above are read from the Story files. An earlier version of this report
transposed M00-02 and M00-04 — calling the PostgreSQL Story "Inertia + React" and
the Inertia Story "Frontend toolchain" — which `MILESTONE_REVIEW_05.md` F02
caught by comparing them against `git log`.

Every Story has a report in `reports/` and a self-review in `review/`.

**Known gap, carried openly:** the eighteen self-reviews are dated `2026-09-06`
and roughly thirty commits have since rewritten parts of what they certify
(`MILESTONE_REVIEW_05.md` F09). The Exit Gate item "Critical = 0 e High = 0 no
review de todas as Stories" is therefore satisfied by reviews of superseded code
for the files those commits touched. Refreshing them is not done here.

## The fifteen Acceptance Criteria

Each maps to a command and its exit code, run at `fe7e1a6` unless stated.

| # | Criterion | Evidence | Exit |
|---|---|---|---|
| 1 | Clean clone starts with one command, serves a rendered Inertia page | `bin/setup` then `bin/dev`; `spec/integration/development_environment_spec.rb`, `spec/requests/inertia_spec.rb` — in `bin/test` | 0 |
| 2 | `db:prepare` on an empty database; migrations reversible or forward-fixed | `spec/integration/database_spec.rb`; `bin/migration-gate` | 0 |
| 3 | A Solid Queue job runs and carries the request's `correlation_id` | `spec/integration/job_correlation_spec.rb`, `spec/integration/jobs_spec.rb` | 0 |
| 4 | Missing required configuration fails with an actionable message and non-zero exit | `spec/integration/boot_configuration_spec.rb` | 0 |
| 5 | `bin/gate local` runs format, lint, typecheck, related tests | `bin/gate local` | 0 |
| 6 | `bin/gate pre-commit` runs Annex I §12.1 and blocks the commit on any failure | the hook ran on every commit in this branch; negative cases in `spec/gates/gate_scripts_spec.rb` | 0 |
| 7 | `bin/gate post-commit` runs Annex I §14.2 and reports objectively | `bin/gate post-commit --story M00-12`; five reason-specific negatives in `spec/gates/gate_scripts_spec.rb` | 0 |
| 8 | AF-01..AF-10 exist, run, report individually, each with a failing negative | `bin/fitness` — 10 functions reported one by one; `spec/gates/fitness_functions_spec.rb` | 0 |
| 9 | CI rejects a PR with typecheck, lint, test or secret failing; job names are stable | **PRs [#2](https://github.com/DouglasPrado/opanel/pull/2)–[#6](https://github.com/DouglasPrado/opanel/pull/6)**, one per class, each blocked — see [`reports/negative-prs/`](reports/negative-prs/) | — |
| 10 | `bin/pack validate` validates every `tasks.json` and fails on invalid state | `bin/pack validate` — 15 milestones; `spec/gates/pack_spec.rb` | 0 |
| 11 | The Stop Gate exists, runs, returns `ok:false` with an objective reason | `bin/stop-gate M00` — 10 checks; `spec/gates/stop_gate_spec.rb` | 0 |
| 12 | `bin/swarm-lab up/down` are idempotent; no test points at production Docker | `spec/integration/swarm_lab_spec.rb`; AF-02 | 0 |
| 13 | `INVENTORY.md` lists the imported components | `app/frontend/components/INVENTORY.md`; `spec/frontend/component_inventory_spec.rb` | 0 |
| 14 | No development secret is versioned, proven over the whole branch history | `bin/security --fast --history` — includes `secret-scan-history` | 0 |
| 15 | ADR, Story Report and Milestone Report templates exist and are referenced | `docs/templates/`; `spec/documentation/templates_spec.rb` | 0 |

### Criterion 9 in full

The Required Test of `M00-11` asks for five pull requests, one per failure class,
each demonstrably blocked. Opened against the **protected** `main`, each planting
one defect verified to fire locally beforehand:

| PR | Criterion | Class | Gate that rejected it | State |
|---|---|---|---|---|
| [#2](https://github.com/DouglasPrado/opanel/pull/2) | AC2 | typecheck | `static` | CLOSED |
| [#3](https://github.com/DouglasPrado/opanel/pull/3) | AC3 | lint | `static` | CLOSED |
| [#4](https://github.com/DouglasPrado/opanel/pull/4) | AC4 | test | `unit` | CLOSED |
| [#5](https://github.com/DouglasPrado/opanel/pull/5) | AC5 | secret | `security-fast` | CLOSED |
| [#6](https://github.com/DouglasPrado/opanel/pull/6) | AC6 | migration | `migrations` | CLOSED |

Closed, never merged. A closed pull request stays verifiable by a third party;
the per-job results are archived in [`reports/negative-prs/`](reports/negative-prs/)
with the cascades explained.

## Quality gates at `fe7e1a6`

| Command | Result | Exit |
|---|---|---|
| `bin/pack validate` | PASS — 15 milestones | 0 |
| `bin/fitness` | PASS — 10 functions, each reported individually | 0 |
| `bin/stop-gate M00` | **OK — the Milestone may stop**; 10 checks PASS | 0 |
| `bin/lint` | PASS | 0 |
| `bin/typecheck` | PASS | 0 |
| `bin/format --check` | PASS | 0 |
| `bin/gate local` | PASS — 9 checks, 462 s | 0 |
| `bin/security --fast --history` | PASS — including `secret-scan-history` | 0 |
| `bin/fitness` | PASS — 10 functions | 0 |
| `bin/gate pre-commit` (hook) | PASS on every commit in this branch | 0 |

### Two things the gate runs taught, recorded because a number alone hides them

**Both commands above failed on their first attempt, with `exit=1`.** The cause
was not the code: the branch of negative PR #5 still existed locally as
`refs/remotes/origin/neg/secret-09082138` after being deleted on the server, so
`secret-scan-history` still reached the planted key. `git fetch --prune` fixed
it and both went green.

That is the third time in this Milestone that "cleaned on one side" was mistaken
for "cleaned": the same shape as the leaked object that stayed served by the API
(F04), and as `security-fast` failing across every open PR while the secret
branch existed. The rule the Milestone leaves behind is narrow and worth stating:
**after deleting a branch that carried a secret, prune the other side and re-run
the scan before claiming anything.**

**`bin/gate local` takes 462 seconds, and 408 of them are the test suite.**
Everything else — format, lint, typecheck, frontend, migrations, contracts — sums
to nine seconds. The suite is slow because it re-enters itself:
`spec/gates/gate_scripts_spec.rb` makes 27 `Open3.capture2e` calls to gate
binaries, one of them `bin/gate`, which runs `bin/test`, which runs the suite
again. Two `rspec` processes are visible during a run, and the outer one spends
its time waiting rather than working.

At three gate runs per Story, M01's 23 Stories carry roughly three hours of
waiting before any of the work is judged. That is a defect in the harness, not in
any Story, and it needs its own Story: the fix — proving the gate against a
minimal fixture repository instead of this one, and leaving the full
`gitleaks dir .` to CI while pre-commit uses `--staged` — is a change to
`lib/gates/` and the gate scripts, which are not edited from inside the work they
judge.

### CI

| | |
|---|---|
| Run | [`34266395044`](https://github.com/DouglasPrado/opanel/actions/runs/34266395044) |
| Commit | `7ddfc63` on `main` |
| Result | **11 of 11 jobs `success`**, 3m39s |
| Jobs | `static` `unit` `integration` `contract` `security-fast` `frontend` `migrations` `setup` `e2e-critical` `swarm-smoke` `pr-gate` |

`merge-gate` reports `skipped` on a push to `main` — it belongs to the merge
stage. On a pull request it runs and currently fails on `required-approvals`:
GitHub does not allow an author to approve their own pull request, so that check
closes only with a human's signature. That is the gate working, not a defect.

**PR [#1](https://github.com/DouglasPrado/opanel/pull/1)** carries `fe7e1a6` —
the commit this report describes — so the handed-over state has its own pipeline
run rather than inheriting one.

## Branch protection

Active on `main` since `2026-09-08`, verified through the API:

```
required_status_checks.contexts = static, unit, integration, contract,
  security-fast, frontend, migrations, setup, e2e-critical, swarm-smoke, pr-gate
allow_force_pushes = false
required_pull_request_reviews.required_approving_review_count = 1
```

Two constraints shape what this means. **The repository had to become public**:
GitHub's free plan refuses branch protection on a private repository. And
**`enforce_admins` is false**, because with one maintainer and no self-approval
an enforcing rule would deadlock the repository. An admin can still bypass; what
changed is that a bypass is now a deliberate act rather than the default.

## The security incident

Recorded here because a reader of this report should not have to find it in a fix
report. Full account: [`FIX_REPORT_04.md`](FIX_REPORT_04.md).

On `2026-09-08`, five negative pull requests carrying planted defects — including
a synthetic RSA private key — were **merged** instead of being closed. `main`
briefly carried the key, a `drop_table :users` migration, a failing spec, a lint
offence and a type error.

The first correction rewound `main` by force-push. It was insufficient: deleting
refs does not delete objects on GitHub, and the commit remained served by the API
while the local repository reported clean. The repository was therefore
**recreated**; `DouglasPrado/opanel` today contains only clean history, and the
object returns `422 No commit found`.

The key was synthetic, 127 bytes, and protected nothing. The cost was real: pull
requests #1–#13 of the previous repository no longer exist, and with them the
public CI evidence of the first negative-test attempt.

Cause: leaving five mergeable pull requests open after CI had already recorded
their results. What prevents a repeat: branch protection, which now refuses a
merge with failing checks, and the rule that a negative pull request is closed as
soon as its result is recorded — applied to PRs #2–#6 above.

## Not done, and named

- **The five Story self-reviews predate their code** (F09). Not refreshed here.
- **`StopGate#milestone_report` still only checks that headings have bodies**
  (F02's second half). Making it require the report to name HEAD and branch is a
  change to `lib/gates/`, which needs its own Story or ADR — a gate is not edited
  from inside the work it judges.
- **The loop's attempt budgets were raised by hand** (F10). `review-state.sh`
  writes `3`/`3` at init and offers no command to change them; this Milestone
  carries `5`/`5`, set in `ca7f2a3`, `4b357cf` and `35be86e`. Each raise was
  authorised and explained in its commit, but the number gating the loop was not
  produced by the loop.
- **Eight Medium and two Low findings** from `MILESTONE_REVIEW_05.md` are
  recorded and not corrected: this state was reached with the fix budget at 5 of
  5, and only blocking findings were addressed.

## Handover

`review-state.json` is `fix_required` at `reviewAttempt` 5 of 5 and `fixAttempt`
5 of 5. Both budgets are exhausted, so this Milestone cannot return to the
automated loop: the next decision is a human's, which is what
`MILESTONE_REVIEW_05.md` §12 recommends.

What is being handed over is a Milestone whose two blocking findings have been
answered in acts — five pull requests genuinely blocked by a protected branch,
and this report rewritten against the commit it describes — with the remaining
gaps named above rather than left to be discovered.
