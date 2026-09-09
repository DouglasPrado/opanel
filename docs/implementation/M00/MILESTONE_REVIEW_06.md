# Milestone Review M00 — Attempt 06

- Reviewer role: Claude independent (read-only)
- Attempt: 06
- HEAD: d576e3081690ebe37fe5759c67430804180d09dd
- Branch: loop/replace-orchestrator

---

# Independent Milestone Review — M00 Foundation, Attempt 06

## 1. Verdict

**NOT_ACCEPTED** — Critical 0, High 3, Medium 8, Low 3.

## 2. Executive Summary

The two blocking findings of `MILESTONE_REVIEW_05.md` were answered unevenly: one is genuinely closed, the other was answered in a way that broke a gate.

**F01 (M00-11's negative Required Test) is closed, and I verified it against GitHub rather than the archive.** Pull requests #2–#6 exist, target the protected `main`, and each is `closed` with `merged:false` (`gh api repos/DouglasPrado/opanel/pulls/{2..6}` → `"state":"closed"`, `"merged":false`, `closed_at` between `21:49:11Z` and `21:49:21Z`). The per-job conclusions I pulled from `repos/DouglasPrado/opanel/commits/<head>/check-runs` match `docs/implementation/M00/reports/negative-prs/pr-0{2..6}-checks.json` field for field: `static=failure` for #2 and #3, `unit=failure` for #4, `security-fast=failure` for #5, `migrations=failure` for #6. That is the criterion, delivered as an act and reconstructible by a third party without the archive. It is the strongest piece of work in this round.

**F02 (the Milestone Report) was answered by rewriting the report, and the rewrite fails the Stop Gate.** `lib/gates/stop_gate.rb:219-249` requires eight named sections. The rewritten `MILESTONE_REPORT.md` has only one of them. Evaluating the gate's own regex against the file at HEAD returns:

```
missing sections: ["Quality", "Findings", "Resultado funcional", "Blocked",
                   "Dependências novas", "Conflitos de especificação",
                   "Human acceptance requested"]
```

So `bin/stop-gate M00` returns `ok:false` at the commit being handed over — while line 124 of that same report states `| bin/stop-gate M00 | **OK — the Milestone may stop**; 10 checks PASS | 0 |`. The sections that vanished are not decoration: `Resultado funcional` is described by the template as "the section a human reads to decide acceptance", and `Findings`, `Blocked`, `Dependências novas`, `Conflitos de especificação` and `Human acceptance requested` are the four Exit Gate questions the human is meant to answer from this file.

**The Milestone reached `ready_for_review` without that gate ever being consulted.** `tools/opanel-loop/hooks/scripts/stop-gate.sh:110-117` runs `bin/stop-gate` and blocks the transition when it is not ok. Commit `d576e30` set `"status": "ready_for_review"` directly in `review-state.json` and raised `maxReviewAttempts` from 5 to 6 — a field `review-state.sh` writes only in `cmd_init` (line 46, value `3`) and exposes no command to change. The handoff therefore skipped the one check that would have caught the broken report.

**A third checkable claim is wrong.** The report says of PR #1 that `merge-gate` "currently fails on `required-approvals` … That is the gate working, not a defect", and presents PR #1 as the handed-over state's own pipeline run. The run (`34281680959`) concluded `failure`: `e2e-critical` is red and the merge-gate job printed two red items, not one — `[ ] ci-green  no result for e2e-critical — a required job that did not run is not a job that passed` and `[ ] required-approvals`. The e2e failure is a bundler network flake (`##[error]The process '…/bundle' failed with exit code 17`), so nothing in the code is broken; what is wrong is the account of it, written 31 minutes after the run finished.

Everything below that line is in good shape, and I re-verified rather than inherited it: the fitness functions plant real violations in synthetic repositories, the boot refuses to start on missing configuration in a real subprocess with `EX_CONFIG`, the correlation id is proved across a real worker process rather than the test adapter, and no invariant of the architecture is broken anywhere in the tree.

## 3. Story Coverage Matrix

| Story | Implementation | Tests | Acceptance Criteria | Result |
|---|---|---|---|---|
| M00-01 Repository and Rails skeleton | `app/{commands,queries,policies,operations,reconcilers,executors,providers}` present; `d85418b` = "feat(skeleton): create the Rails 8.1 Control Plane application" | `spec/architecture/repository_layout_spec.rb` | met | PASS |
| M00-02 PostgreSQL and migrations | `bin/migration-gate`, `lib/gates/migration_gate.rb` | `spec/gates/migration_gate_spec.rb`, `spec/integration/database_spec.rb` | met | PASS |
| M00-03 Solid Queue baseline | `app/jobs/`, `lib/opanel/queues.rb` | `spec/integration/{jobs,queue_configuration,worker_crash}_spec.rb` | met | PASS |
| M00-04 Inertia + React + Vite | Inertia stack; `app/frontend/{pages,entrypoints,lib,types}` | `spec/requests/inertia_spec.rb`, Playwright smoke | met | PASS |
| M00-05 Component import and inventory | `app/frontend/components/{ui,shared,features,layouts}`, `INVENTORY.md` (150 lines) | `spec/frontend/component_inventory_spec.rb` | met | PASS |
| M00-06 Local development environment | `bin/setup`, `bin/dev`; CI `setup` job runs `bin/setup --skip-server` twice | `spec/integration/development_environment_spec.rb` | met | PASS |
| M00-07 Backend test harness | RSpec + FactoryBot on real PostgreSQL | `spec/integration/test_harness_spec.rb` | met | PASS |
| M00-08 Frontend and E2E harness | Vitest, Playwright, `bin/redact-artifacts` | `spec/security/artifact_redaction_spec.rb` | met | PASS |
| M00-09 Lint, format, typecheck | RuboCop, ESLint, `tsc`, `bin/suppression-gate` | `spec/gates/lint_rules_spec.rb` | met | PASS |
| M00-10 Security scanning baseline | `bin/security`, anchored allowlist, waivers, Dependency Gate | `spec/security/security_scan_spec.rb:129` scans tree **and** history | met | PASS |
| M00-11 CI pipeline and gates | Pipeline green at `7ddfc63`; branch protection real; five negative PRs closed unmerged with the class-owning gate red | `spec/gates/ci_pipeline_spec.rb`; live check-runs match the archive | AC2–AC6 now proved on real pull requests; **AC11 enforced only in shape** (M04) | PARTIAL |
| M00-12 Quality gate scripts | `bin/gate local/pre-commit/post-commit`, hook, boundary check | `spec/gates/gate_scripts_spec.rb` (27 `Open3.capture2e` calls — the report's number is correct) | met | PASS |
| M00-13 Fitness functions AF-01..AF-10 | `lib/gates/fitness_functions.rb`, ten ids, reported individually | negative per function against a synthetic repo | met, but `docker_boundaries` carries three extra paths with no ADR (M05) | PARTIAL |
| M00-14 Autonomous loop scaffolding | `bin/pack`, `bin/stop-gate`, schemas, `review-state.sh` | `spec/gates/{pack,stop_gate}_spec.rb` | **the Stop Gate is red at HEAD and was bypassed** (F01, F02) | **FAIL** |
| M00-15 Structured logging and health | `lib/opanel/{log_formatter,correlation_middleware}.rb`, `HealthController` (503 + classified cause, no version/host leak) | `spec/integration/job_correlation_spec.rb` proves the id across a real worker | met | PASS |
| M00-16 Configuration and secrets | `lib/opanel/configuration.rb:200-208` aborts with `EXIT_CODE` | `spec/integration/boot_configuration_spec.rb` boots a real subprocess | met | PASS |
| M00-17 Swarm lab harness | `bin/swarm-lab`, `lib/gates/swarm_lab.rb` resolves the endpoint the CLI would use and refuses a non-lab daemon | `spec/integration/swarm_lab_spec.rb`; `swarm-smoke` green at `7ddfc63` | met | PASS |
| M00-18 Documentation templates | `docs/templates/` (8 files), referenced by the gates | `spec/documentation/templates_spec.rb` | met — but the Milestone's own report no longer follows the template (F01) | PASS |
| **Milestone artefact** | `MILESTONE_REPORT.md` | — | Exit Gate bullets 3 and 4 unmet; `README.md:144`, `GOAL.md:20` | **FAIL** |

## 4. Test Results

Read-only; nothing executed beyond `git`, `gh` and one regex evaluation that reads a file.

- **Green, at `7ddfc63`.** Run `34266395044`, push to `main`: eleven jobs `success`, `merge-gate` `skipped`. `security-fast` runs `bin/test --type security` (`config/ci/jobs.yml:66`), which contains `spec/security/security_scan_spec.rb:129` — `bin/security --fast --history`. Milestone AC14 is reconstructible at that commit.
- **`7ddfc63..d576e30` is documentation only** — seventeen files, all under `docs/`. So the green run covers every executable file at HEAD. That is the honest mitigation for everything that follows about CI, and I weighed it.
- **Red, at the branch head that exists on the server.** Run `34281680959` for `fe7e1a6` concluded `failure` (`e2e-critical`), for an infrastructure reason.
- **Nothing at HEAD.** `git ls-remote origin` puts `refs/heads/loop/replace-orchestrator` at `fe7e1a6`; `d576e30`, `e2b575f` and `e00ceb0` have never been pushed. `docs/implementation/M01/tasks.json` grew by 274 lines in `e2b575f`, after the last `static` run that would have validated it. I checked it by hand: 24 stories, every `file` exists, every `dependsOn` resolves, no cycle, schema-shaped.
- **Test quality.** 38 spec files. The gate suites run the real binaries against planted failures; `lib/gates/post_commit.rb:166-208` still refuses test evidence whose `commit` is not HEAD or whose run was narrowed. No weakened assertion, no scanner exclusion, no disabled rule found.
- **Not reconstructible.** Every row of the report's "Quality gates at `fe7e1a6`" table (`:118-131`) is an implementer claim: `tmp/` is gitignored. One of them — the Stop Gate row — is demonstrably false at HEAD. The table also lists `bin/fitness` twice.

## 5. Quality Gate Results

| Gate | State at HEAD | How verified |
|---|---|---|
| `bin/stop-gate M00` | **`ok:false`** — `milestone-report` fails on seven missing sections | `lib/gates/stop_gate.rb:219-249` evaluated against the file |
| `bin/gate local` / `pre-commit` / `post-commit` | Structurally sound; last green recorded in `tmp/`, which is gitignored | `bin/gate:155-223` |
| `bin/fitness` | Green inside `static` at `7ddfc63`; ten functions, `AF-01`..`AF-10` | run `34266395044`; `lib/gates/fitness_functions.rb` |
| `bin/pack validate` | 15 milestone `tasks.json` present; M01's post-dates the last run | directory listing + manual validation |
| `bin/security` (tree + history) | Green at `7ddfc63` | `security-fast` success; `config/ci/jobs.yml:66` |
| `pr-gate` | Aggregates `pr-stage` only — `success` on PR #1 while `e2e-critical` was red | `.github/workflows/ci.yml:186-205`; check-runs for `fe7e1a6` |
| `merge-gate` | `pull_request`-only; **still not a required context** | `ci.yml:215`; protection API |
| Branch protection | 11 contexts, CODEOWNERS review, `strict:true`, no force push; `enforce_admins:false` | `gh api .../branches/main/protection` |
| Stop hook | Would have blocked the handoff; was not consulted | `tools/opanel-loop/hooks/scripts/stop-gate.sh:110-120` vs `d576e30` |

## 6. Architecture Review

No invariant violation. `app/models/` holds only `ApplicationRecord`, `Current` and `InfrastructureCheckpoint` — no domain entity, as M00 requires. `git grep` for `docker.sock|DOCKER_HOST` outside `bin/swarm-lab`, `lib/gates/{swarm_lab,fitness_functions,workspace_guardrail}.rb`, `config/architecture/*` and the specs returns nothing; no controller carries domain logic; no callback triggers an external effect; no speculative abstraction — every `lib/gates/*` module has a caller and a test. `app/frontend/components/{ui,shared,features,layouts}` keeps the categories `AGENT_RULES.md` requires visible.

The one governance gap is unchanged from the last round: `config/architecture/fitness.yml:50-56` lists `spec/support/swarm_lab`, `bin/swarm-lab` and `lib/gates/swarm_lab.rb` under `docker_boundaries` while its own comment says adding a path there "is a Tier-0 security change … It needs an ADR, not a Story"; `docs/decisions/` holds ADR-0001..0004 and nothing on this.

## 7. Security Review

The controls are well built and I found no way past them: `bin/security` never echoes a detected value, `bin/redact-artifacts` runs before upload, `config/security/gitleaks.toml`'s `^tmp/` anchoring is correct, every allowlist entry carries a written reason, and `lib/gates/workspace_guardrail.rb` checks credential *shapes* and *destinations* rather than variable names alone.

One residual, and it is the shape this Milestone has already been burned by twice. The negative test for AC5 planted `config/ci_negative_key.pem` — a three-line `BEGIN RSA PRIVATE KEY` block, 127 bytes — on `neg/secret-09082138`. The branch is deleted, but the object is still served by the public repository: `gh api "repos/DouglasPrado/opanel/contents/config/ci_negative_key.pem?ref=fb02f0210f059f726d0be6900c6ba13215f8511f"` returns the file, reachable through `refs/pull/5/head`. The report's own lesson — "after deleting a branch that carried a secret, prune the other side and re-run the scan before claiming anything" — describes the local side of exactly this and does not mention the server side. The material is synthetic and protects nothing; the pattern is the one that cost this Milestone a repository.

## 8. Scope Review

No scope creep into a later Milestone's *implementation*, no missing scope, no unjustified dependency. `e2b575f` files `M01-00` — a Story to bring `bin/gate local` back inside its time budget — into M01 rather than M00, with the reasoning that a gate is not edited from inside the work it judges. That is the right call and correctly placed. It does mean `docs/implementation/M01/tasks.json` changed after the last run of the gate that validates it.

## 9. Findings by Severity

### Critical (0)

None.

### High (3)

**F01 — `bin/stop-gate M00` is red at HEAD, and the Milestone Report claims it is green.**
`lib/gates/stop_gate.rb:219-222` requires the sections `Stories`, `Quality`, `Findings`, `Resultado funcional`, `Blocked`, `Dependências novas`, `Conflitos de especificação`, `Human acceptance requested`, each with a body longer than three characters (`:241-244`). `docs/implementation/M00/MILESTONE_REPORT.md` has headings at lines 17, 39, 78, 118, 182, 199, 224 and 240; only `## Stories` (`:39`) matches. `## Quality gates at \`fe7e1a6\`` (`:118`) does not satisfy `^#{2,3}\s+Quality\s*$`. Evaluating the gate's own expression against the file returns `missing sections: ["Quality", "Findings", "Resultado funcional", "Blocked", "Dependências novas", "Conflitos de especificação", "Human acceptance requested"]`. Line 124 of the same file states `| bin/stop-gate M00 | **OK — the Milestone may stop**; 10 checks PASS | 0 |`. **Impact:** `GOAL.md:20` ("`bin/stop-gate` … devolve `ok:true` no estado final") and `README.md:144` (Exit Gate: the Stop Gate executes with exit code 0 in the final state) are unmet, and the content the human acceptance decision needs is gone — `docs/templates/MILESTONE_REPORT.md:72-75` calls `Resultado funcional` "the section a human reads to decide acceptance", and there is no longer a `Findings` table, a `Blocked` line, a `Dependências novas` list (an Exit Gate item at `README.md:149`), a `Conflitos de especificação` line or a `Human acceptance requested` section. **Fix:** restore the eight template sections, keeping the new material (the fifteen criteria, the incident, the branch-protection settings) inside them, and re-run `bin/stop-gate M00` at the commit that is handed over.

**F02 — the transition to `ready_for_review` bypassed the gate that would have refused it, and the review budget was raised by hand.**
`tools/opanel-loop/hooks/scripts/stop-gate.sh:110-120` runs `bin/stop-gate "$MILESTONE"` and, when `ok` is not `true`, blocks with the failing check names instead of setting the state. `d576e30` writes `docs/implementation/M00/review-state.json` directly: `"status": "fix_required"` → `"ready_for_review"` and `"maxReviewAttempts": 5` → `6`. `tools/opanel-loop/scripts/review-state.sh` writes `maxReviewAttempts` only in `cmd_init` (`:46`, value `3`) and exposes no command to change it — `case "$COMMAND"` at `:184-197` lists `init status set review-start verdict fix-start fix-done block error attempt-number`. Once the status is `ready_for_review` the hook takes the branch at `:61-63` and never re-runs the gate. The round that produced these fixes also recorded no `fix-start` and produced no `FIX_REPORT_05.md`; `docs/implementation/M00/` holds `FIX_REPORT_01..04` only, while `MILESTONE_REPORT.md:242-245` still asserts the Milestone "cannot return to the automated loop". **Impact:** the Exit Gate was never mechanically verified for this handoff; the Milestone under review is in a state its own Stop Gate rejects, which is exactly what `CLAUDE.md` means by "`review-state.sh` owns those transitions". **Fix:** route the transition through `review-state.sh` so the hook's gate runs; give the script an explicit, recorded command for the budgets rather than a hand edit; record the work that answered `MILESTONE_REVIEW_05` in a fix report of its own.

**F03 — the Milestone Report misreports the CI state of the commit it hands over.**
`docs/implementation/M00/MILESTONE_REPORT.md:173-180`: "On a pull request it runs and currently fails on `required-approvals` … That is the gate working, not a defect. **PR #1** carries `fe7e1a6` — the commit this report describes — so the handed-over state has its own pipeline run rather than inheriting one." The run for `fe7e1a6` is `34281680959` and concluded `failure`. `gh api repos/DouglasPrado/opanel/commits/fe7e1a6.../check-runs` returns `e2e-critical=failure`; the merge-gate job (`102248575483`) printed:

```
  [ ] ci-green                     no result for e2e-critical — a required job that did not run is not a job that passed
  [ ] required-approvals           the pull request is REVIEW_REQUIRED
merge-gate: FAIL
```

The e2e job failed in `ruby/setup-ruby` with `Network error while fetching` / `bundle failed with exit code 17` — infrastructure, not code — and the run finished at `21:41:58Z`, 31 minutes before `e00ceb0` was committed at `22:12:42Z`. **Impact:** `README.md:145` requires "o pipeline de CI está verde em uma execução completa do branch"; the only run of this branch is red, and the report tells the human that the sole red item is a signature it is waiting for. A reader following the report would accept a Milestone believing nothing else is failing. **Fix:** re-run the pipeline on the branch until it is green at the handed-over commit and cite that run, or state plainly that the branch run failed, on which job, and why the green run at `7ddfc63` covers the code (the delta is documentation only — that argument is available and true, and it is the one the report should be making).

### Medium (8)

**M01 — the planted private-key block is still served by the public repository.** `gh api "repos/DouglasPrado/opanel/contents/config/ci_negative_key.pem?ref=fb02f0210f059f726d0be6900c6ba13215f8511f"` returns the 127-byte file; the commit is reachable through `refs/pull/5/head`, which `git ls-remote origin` lists. `MILESTONE_REPORT.md:97` records AC14 as PASS via `bin/security --fast --history` and `:135-146` describes only the local remote-tracking ref as the thing that had to be pruned. The material is synthetic, so this is not a leak — but the same "cleaned on one side" shape is what the report itself names as this Milestone's recurring lesson. Fix: disclose it, and prefer a detectable non-key fixture (or a private scratch repository) for the next AC5 rehearsal.

**M02 — `AcceptanceMapping` accepts a criterion when any one quoted token resolves.** `lib/gates/acceptance_mapping.rb:68` — `text.scan(QUOTED).flatten.any? { … }` — with `named_in_code?` (`:84-89`) accepting any string of six or more characters containing three letters that appears anywhere in a corpus spanning `spec/**`, `app/**`, `lib/**`, `bin/*`, `config/**`, `db/**`, `.github/**`. One real reference and four invented ones passes. Carried unfixed from `MILESTONE_REVIEW_05` F05.

**M03 — `bin/merge-gate`'s `ci_green` ignores provenance.** `bin/merge-gate:149` reads only `JSON.parse(File.read(path))["result"]`, while `bin/_gate_lib.sh` records `commit`, `branch` and `dirty` in every result and `lib/gates/post_commit.rb:176-181` enforces exactly that field. A result from another commit or a dirty tree satisfies the merge gate. Carried unfixed (F06).

**M04 — `pipeline_change_authorised` attributes authorisation to a commit range.** `bin/merge-gate:292-301` scans `git log --format=%s%n%b "$base...HEAD"` for any `M\d\d-\d\d`/`ADR-\d{4}` token, so a pipeline change passes whenever *any* commit in the range names *any* Story. M00-11 AC11 ("uma alteração no pipeline … não pode ser feita como efeito colateral de outra Story") is therefore enforced in shape only, and `spec/gates/ci_pipeline_spec.rb` tests it by grepping the script's own source for constant names. Carried unfixed (F07).

**M05 — AF-02's Tier-0 boundary was widened without the ADR the file demands.** `config/architecture/fitness.yml:50-56` lists three paths beyond `app/executors/`; lines 46-49 of the same file say adding one "is a Tier-0 security change … It needs an ADR, not a Story". `docs/decisions/` contains ADR-0001..0004 and nothing on this. Carried unfixed (F08).

**M06 — the eighteen Story self-reviews predate the code they certify.** Every file under `docs/implementation/M00/review/` is dated `2026-09-06`; roughly thirty-five commits have since rewritten `bin/redact-artifacts`, `config/security/gitleaks.toml`, `lib/gates/swarm_lab.rb`, the CI workflow and several specs. The Exit Gate's "Critical = 0 e High = 0 no review de todas as Stories" is satisfied by reviews of superseded code. Disclosed in `MILESTONE_REPORT.md:73-76`; still open (F09).

**M07 — `merge-gate` is not a required status check.** `gh api .../branches/main/protection` returns eleven contexts and `merge-gate` is not among them; `ci.yml:215` restricts it to `pull_request`. The Annex I §15.2 checklist runs on every pull request and is required by nothing. Carried unfixed (F04).

**M08 — the reviewed state has never been pushed or built.** `git ls-remote origin` puts the branch at `fe7e1a6`; `e00ceb0`, `e2b575f` and `d576e30` exist only locally. `docs/implementation/M01/tasks.json` changed by 274 lines in `e2b575f`, after the last `static` job that would have run `bin/pack validate` over it. I validated it by hand and it is well-formed, but the gate has not seen it.

### Low (3)

**L01 — `pr-gate` evaluates one aggregate, not the named jobs.** `.github/workflows/ci.yml:183-185` claims "this check requires every named job — 'nothing red' is not the condition", but `needs: [pr-stage]` (`:189`) yields a single matrix aggregate and excludes `merge-stage` entirely. Demonstrated on PR #1: `pr-gate=success` while `e2e-critical=failure`. Mitigated because both job names are individually required contexts. Fix the comment or list the jobs.

**L02 — two comments overstate what the CI job runs.** `bin/gate:202` and `bin/security:101` say the `security-fast` job "scans the whole tree and the history", while `config/ci/jobs.yml:64` invokes `bin/security --out …` without `--history`; the history scan reaches CI only through the `controls` command (`:66`).

**L03 — the negative-PR archive contradicts the table it supports.** `docs/implementation/M00/reports/negative-prs/pr-0{2..6}.json` each record `"state": "OPEN"`, while `negative-prs/README.md` and `MILESTONE_REPORT.md:108-112` state `CLOSED`. The live API says closed, so the tables are right and the capture was simply taken minutes early — but the archive exists to be the evidence, and it currently says the opposite of the claim.

## 10. Required Fixes

1. Restore the eight sections of `docs/templates/MILESTONE_REPORT.md` in `MILESTONE_REPORT.md`, keeping the new material inside them, and re-run `bin/stop-gate M00` until it returns `ok:true` at the handed-over commit. (F01)
2. Move the `ready_for_review` transition back behind `review-state.sh` so the Stop hook's gate runs; add an explicit, recorded command for the attempt budgets; record the round that answered `MILESTONE_REVIEW_05` in its own fix report. (F02)
3. Correct the CI section: cite a green run at the commit being handed over, or state which job failed, why, and why the green run at `7ddfc63` covers the code. (F03)
4. Disclose the planted key still served at `refs/pull/5/head`, and decide whether it stays. (M01)
5. Harden the three gates that accept shape: every quoted reference must resolve; `ci_green` must reject stale or dirty provenance; `pipeline_change_authorised` must attribute to the commit that changed the pipeline and be tested against planted diffs. (M02, M03, M04)
6. Write the Tier-0 ADR for `docker_boundaries` or narrow the list; refresh the self-reviews; add `merge-gate` to the required contexts; push the branch. (M05, M06, M07, M08)

## 11. Evidence

Read: `CLAUDE.md`, `docs/AGENT_RULES.md`, `docs/goals/REVIEW_MILESTONE.md`; `docs/implementation/M00/{README.md,GOAL.md,tasks.json,review-state.json,MILESTONE_REPORT.md,MILESTONE_REVIEW_05.md}`; `stories/M00-11-ci-pipeline-and-gates.md`; `reports/negative-prs/{README.md,pr-0*.json}`; the eighteen files under `review/`; `docs/templates/MILESTONE_REPORT.md`; `.github/workflows/ci.yml`; `config/ci/jobs.yml`, `config/architecture/fitness.yml`, `config/pack/tasks.schema.json`; `bin/{gate,merge-gate,security,stop-gate}`; `lib/gates/{acceptance_mapping,pack,review_findings,stop_gate,fitness_functions,workspace_guardrail}.rb`; `app/controllers/health_controller.rb`; `spec/integration/{job_correlation,boot_configuration}_spec.rb`, `spec/security/security_scan_spec.rb`, `spec/gates/fitness_functions_spec.rb`; `tools/opanel-loop/{hooks/scripts/stop-gate.sh,scripts/review-state.sh}`; `docs/implementation/M01/tasks.json`.

Read-only commands: `git log/show/diff/status/ls-remote/grep/rev-parse`; `gh api repos/DouglasPrado/opanel/{pulls/1..6, commits/<sha>/check-runs, commits/<sha>, contents/…, branches/main/protection}`, `gh run list`, `gh run view --job --log`; one `ruby -e` that reads `MILESTONE_REPORT.md` and evaluates the Stop Gate's section expression. Nothing in the workspace was modified; `git status` still shows only the runner's pre-existing modification to `docs/implementation/M00/review-state.json`.

## 12. Final Recommendation

Hold M00 at **NOT_ACCEPTED**, and be precise about what is left. The Milestone's hardest outstanding debt — five pull requests demonstrably blocked by a protected branch — is paid, and paid in a form I could verify against GitHub without touching the implementer's archive. The engineering underneath has been solid for three rounds and still is.

What blocks acceptance is smaller than what was blocked last time, and more self-inflicted. Answering "the report describes the wrong commit" by rewriting the report broke the gate that reads the report, and the broken gate was not noticed because the state that would have run it was set by hand. That is one loop, closed on itself: a Milestone whose Stop Gate says it may not stop, handed over saying it may. The fix is an afternoon — restore the template's sections, move the transition back behind the script, and correct three sentences about the pipeline — but it has to be the gate saying so, not the report.

---

## Counts

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 3 |
| Medium | 8 |
| Low | 3 |

Verdict: **NOT_ACCEPTED**
