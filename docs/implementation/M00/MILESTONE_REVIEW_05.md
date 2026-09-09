# Milestone Review M00 — Attempt 05

- Reviewer role: Claude independent (read-only)
- Attempt: 05
- HEAD: 03435fb4dc3dd85096a3e08ef7bd1832272d4bcc
- Branch: loop/replace-orchestrator

---

# Independent Milestone Review — M00 Foundation, Attempt 05

## 1. Verdict

**NOT_ACCEPTED** — Critical 0, High 2, Medium 8, Low 2.

## 2. Executive Summary

This round closed real ground. Three of attempt 04's four blocking findings are genuinely answered, and I verified each against the source rather than the report:

- **F01 (red pipeline)** — run `34266395044` at `7ddfc63` concludes `success` with eleven jobs green (`static unit integration contract security-fast frontend migrations setup e2e-critical swarm-smoke pr-gate`), `merge-gate` `skipped` because it is `pull_request`-only (`.github/workflows/ci.yml:215`). The report's "11 of 11" is accurate.
- **F03 (nothing enforced)** — `gh api repos/DouglasPrado/opanel/branches/main/protection` now returns eleven required contexts, `allow_force_pushes:false`, `allow_deletions:false`, `require_code_owner_reviews:true`, `required_approving_review_count:1`. `enforce_admins:false`, disclosed in `FIX_REPORT_04.md:145-150`.
- **F04 (leaked private key)** — materially closed. `git log --all -- config/ci_negative_key.pem` is empty locally, and `gh api repos/DouglasPrado/opanel/commits/f797866c805a` returns `422 No commit found`. The incident, the force-pushes and the repository recreation are now recorded in `FIX_REPORT_04.md:152-210`, which is the record whose absence was the finding.

The engineering underneath remains strong and I re-verified it rather than inheriting the judgement: the fitness functions each plant a violation in a synthetic repository (`spec/gates/fitness_functions_spec.rb`), the five CI failure classes are proved by planting a real defect and running the real command (`spec/gates/ci_pipeline_spec.rb:154-241`), and `lib/gates/post_commit.rb:166-208` refuses test evidence whose `commit` is not HEAD, whose `tests` count is zero, or whose run was narrowed — the single best piece of "content, not shape" checking in the repository.

Two things block acceptance.

**M00-11's negative Required Test is still unmet, and its evidence is unverifiable.** The implementer hands this back open and argued (`FIX_REPORT_04.md:70-117`), which is honest; the call is mine, and the archive fails it. Every artefact it points at is gone: PRs #5/#7/#9/#10/#11 return `404`, their head commits return `422`, and the run links address a repository that no longer exists. What the archive does record is that each PR was **`MERGED`** after going red — the opposite of "comprovadamente bloqueado".

**`MILESTONE_REPORT.md` — the artefact the human acceptance gate reads — still describes another commit on another branch, and is now false in several checkable places.** It names `Branch: docs/agent-bootstrap`, `Head: f32a344` (30 commits back), states "Independent review has not been performed" when four reviews have, mislabels two Story titles against `tasks.json`, never maps the Milestone's fifteen acceptance criteria at all, and mentions neither the leaked key, the branch rewrite, the repository recreation nor the decision to make the repository public. The Exit Gate requires those criteria to be satisfied *with evidence in that file* (`README.md:143`). The Stop Gate cannot catch it: `lib/gates/stop_gate.rb:228-249` checks only that eight headings exist with more than three characters under them.

## 3. Story Coverage Matrix

| Story | Implementation | Tests | Acceptance Criteria | Result |
|---|---|---|---|---|
| M00-01 Repository and Rails skeleton | Boundary dirs present; `d85418b` matches `tasks.json` | `spec/architecture/repository_layout_spec.rb` | met | PASS |
| M00-02 PostgreSQL and migrations | `bin/migration-gate`, two migrations, `db/` | `spec/gates/migration_gate_spec.rb`, `spec/integration/database_spec.rb` | met | PASS |
| M00-03 Solid Queue baseline | `lib/opanel/queues.rb`, `app/jobs/*` | `spec/integration/jobs_spec.rb` | met | PASS |
| M00-04 Inertia + React + Vite | Inertia stack, `app/frontend/` | `spec/requests/inertia_spec.rb`, e2e smoke | met | PASS |
| M00-05 Component import and inventory | `app/frontend/components/INVENTORY.md` (150 lines, categorised, gallery-linked) | `spec/frontend/component_inventory_spec.rb` | met, two strictness flags disclosed | PASS |
| M00-06 Local development environment | `bin/setup`, `bin/dev`; CI `setup` job runs it twice on a clean checkout | `spec/integration/development_environment_spec.rb` | met | PASS |
| M00-07 Backend test harness | RSpec + FactoryBot on real PostgreSQL | `spec/integration/test_harness_spec.rb` | met | PASS |
| M00-08 Frontend and E2E harness | Vitest, Playwright, `bin/redact-artifacts` | `spec/security/artifact_redaction_spec.rb` | met | PASS |
| M00-09 Lint, format, typecheck | RuboCop, ESLint, `tsc`, suppression gate | `spec/gates/lint_rules_spec.rb` | met | PASS |
| M00-10 Security scanning baseline | `bin/security`, anchored allowlist with reasons, waivers, Dependency Gate | `spec/security/security_scan_spec.rb` | met | PASS |
| M00-11 CI pipeline and gates | Pipeline green once at `7ddfc63`; branch protection now real | `spec/gates/ci_pipeline_spec.rb` proves the five classes **locally**, not on pull requests | Required Test "cinco PRs … comprovadamente bloqueado" unmet; evidence unverifiable (404/422) | **FAIL** |
| M00-12 Quality gate scripts | `bin/gate local/pre-commit/post-commit`, hook, boundary check | `spec/gates/gate_scripts_spec.rb`, negative per pre-commit item | met | PASS |
| M00-13 Fitness functions AF-01..AF-10 | `lib/gates/fitness_functions.rb`, reported individually | negative per function | met, but `docker_boundaries` carries three extra paths with no ADR | PARTIAL |
| M00-14 Autonomous loop scaffolding | `bin/pack`, `bin/stop-gate`, schemas, `review-state.sh` | `spec/gates/{pack,stop_gate}_spec.rb` | met, but the acceptance verifier accepts one resolving token and the state file is edited outside its owner | PARTIAL |
| M00-15 Structured logging and health | `lib/opanel/{log_formatter,correlation_middleware}.rb`, `HealthController` | `spec/requests/health_spec.rb`, `spec/unit/log_formatter_spec.rb` | met | PASS |
| M00-16 Configuration and secrets | `lib/opanel/configuration.rb:161,200-208` — fail-closed with `EX_CONFIG` | `spec/integration/boot_configuration_spec.rb` | met | PASS |
| M00-17 Swarm lab harness | `bin/swarm-lab`, `lib/gates/swarm_lab.rb`; `swarm-smoke` green in CI | `spec/integration/swarm_lab_spec.rb` | met | PASS |
| M00-18 Documentation templates | `docs/templates/` (8 files), referenced by the gates | `spec/documentation/templates_spec.rb` | met | PASS |
| **Milestone artefact** | `MILESTONE_REPORT.md` | — | Exit Gate items at `README.md:143,150` unmet | **FAIL** |

## 4. Test Results

Read-only; nothing executed. What is reconstructible from the repository:

- **Green, at `7ddfc63`.** Run `34266395044`, `push` to `main`: eleven jobs `success`, `merge-gate` `skipped`. `security-fast` runs `bin/test --type security` (`config/ci/jobs.yml:66`), which includes the tree-and-history example — so Milestone AC14 is reconstructible at that commit.
- **Nothing at HEAD.** `gh run list` returns exactly two runs in the recreated repository; neither has `headSha 03435fb`. `git ls-remote origin` lists only `refs/heads/main` at `7ddfc63` — the branch under review has never been pushed. The delta `7ddfc63..03435fb` is two documentation files.
- **Not reconstructible.** `MILESTONE_REPORT.md:64-79` ("554 examples", per-gate exit codes) describes `f32a344` on `docs/agent-bootstrap`; `tmp/` is gitignored. Rejected as evidence.
- **Test quality.** 38 spec files, 588 examples declared. The gate suites run the real scripts against planted failures; the CI negatives use a GitHub-PAT-shaped token in a path a real leak could occupy and assert the value is never printed (`spec/gates/ci_pipeline_spec.rb:200-222`); no weakened assertion or scanner exclusion was found. `git grep` for credential shapes across the tree returns only declared fixtures.

## 5. Quality Gate Results

| Gate | State | How verified |
|---|---|---|
| `bin/gate local` / `pre-commit` / `post-commit` | Structurally sound; last recorded green in reports, not at HEAD | `bin/gate:155-230`; `tmp/` gitignored |
| `bin/fitness` | Green inside `static` at `7ddfc63` | run `34266395044` |
| `bin/pack validate` | 15 milestones present under `docs/implementation/` | directory listing + `static` job |
| `bin/security` (tree + history) | Green at `7ddfc63` | `security-fast` success; `config/ci/jobs.yml:66` |
| `pr-gate` | Green at `7ddfc63`, and now a required context | run + protection API |
| `merge-gate` | Runs on `pull_request` only; **not a required status check** | `ci.yml:215`; protection `contexts` list |
| Branch protection | Active: 11 contexts, CODEOWNERS review, no force push; `enforce_admins:false` | `gh api .../branches/main/protection` |
| Stop Gate `milestone_report` | Passes a report about another commit | `lib/gates/stop_gate.rb:228-249` |

## 6. Architecture Review

No invariant violation. No domain entity (`app/models/` holds only `Current`, `ApplicationRecord`, `InfrastructureCheckpoint`); `git grep docker.sock|DOCKER_HOST` outside the declared boundary and the checkers themselves returns nothing; no controller carries domain logic; no callback triggers an external effect; no speculative abstraction — every `lib/gates/*` module has a caller and a test. The one boundary concern is governance: `config/architecture/fitness.yml:51-56` lists `spec/support/swarm_lab`, `bin/swarm-lab` and `lib/gates/swarm_lab.rb` in `docker_boundaries`, while the file's own comment says adding a path there "needs an ADR, not a Story"; `docs/decisions/` holds ADR-0001..0004 and nothing on this.

## 7. Security Review

The controls are well built. `bin/security` never echoes a detected value; `bin/redact-artifacts` runs before upload; the `^tmp/` anchoring in `config/security/gitleaks.toml:38` is correct and every allowlist entry carries a written reason, value by value rather than by file. The leaked key is provably gone from the server (`422`) and from local history.

Two residual observations. The repository was made **public** to obtain branch protection (`FIX_REPORT_04.md:138-144`) — a deliberate trade, but one that is not mentioned in the artefact the human is asked to accept. And `enforce_admins:false` plus `merge-gate` absent from the required contexts means the Annex I §15.2 checklist — Critical/High = 0, base current, migration rollout, Story state — is executed on every PR and required by nothing; the archive at `reports/negative-prs/pr-11-checks.json` shows `merge-gate` `FAILURE` on all five negative PRs, which were merged anyway.

## 8. Scope Review

No scope creep, no missing scope beyond M00-11's negative Required Test, no overengineering, no unjustified dependency. Loop changes made during the round (`4d2fb44`) are covered by `ADR-0004`.

## 9. Findings by Severity

### Critical (0)
None.

### High (2)

**F01 — M00-11's negative Required Test is unmet and its evidence cannot be reconstructed.**
`docs/implementation/M00/stories/M00-11-ci-pipeline-and-gates.md:60` requires "cinco PRs de teste, um por classe de falha (2–6), cada um comprovadamente bloqueado", and its Definition of Done (`:66`) repeats it. What exists is `docs/implementation/M00/reports/negative-prs/` — an implementer-generated JSON capture. Every referent is gone: `gh api repos/DouglasPrado/opanel/pulls/{5,7,9,10,11}` → `404 Not Found`; `gh api .../commits/f797866c805a` (and `972c76a62309`, `ea19516f7e03`) → `422 No commit found`; the `actions/runs/34255676939/...` links in `pr-11-checks.json` address the deleted repository. What the archive positively records is `{"state":"MERGED","mergedAt":"2026-09-08T17:34:57Z"}` in `pr-11.json` — the five PRs were merged after going red, which is the opposite of the criterion. `reports/M00-11.md` (Pendências) still says the five cases are "proven locally … When the first PR exists, the same five should be confirmed as blocked", yet `tasks.json:130` records M00-11 `done`. **Impact:** the Story's DoD and Milestone AC9's enforcement half rest on evidence a third party cannot check, and on an episode whose record shows the gate not blocking. **Fix:** open five pull requests against the now-protected `main`, one per class, and leave the failing checks visible (close, do not merge); or replace the criterion by an explicit Story/ADR and correct `tasks.json`.

**F02 — `MILESTONE_REPORT.md` describes a different state and is false at HEAD; the Exit Gate items that depend on it are unmet.**
`docs/implementation/M00/MILESTONE_REPORT.md:6-8` records `Branch: docs/agent-bootstrap`, `Head: f32a344`; `:64` says "Commands run on `f32a344`"; `:217-219` says "Independent review has not been performed", which four review rounds contradict; `:41` titles M00-02 "Inertia + React + Vite integration" and `:43` titles M00-04 "Frontend toolchain and HMR", while `git log -1 --format=%s 86163d7` is "feat(database): connect PostgreSQL and gate migrations" and `7241a05` is the Inertia commit. The file contains no mapping of the fifteen Milestone acceptance criteria, and mentions neither the leaked key, the force-pushed rewrite, the repository recreation, nor the decision to make the repository public. `README.md:143` requires "os 15 Acceptance Criteria acima … satisfeitos com evidência (comando + exit code) no `MILESTONE_REPORT.md`" and `:150` requires it "gerado com evidências objetivas". `lib/gates/stop_gate.rb:228-249` cannot detect any of this: it verifies a `Status:` line and that eight named headings have bodies longer than three characters. **Impact:** the human acceptance gate would be exercised against an account of a 30-commit-old state that omits a security incident and a visibility change; a declared Exit Gate condition is unmet. **Fix:** regenerate the report against the handed-over commit with the fifteen criteria mapped to commands and exit codes, name the CI run id, record the incident and the public-repository trade, and extend `StopGate#milestone_report` to require the report to name HEAD and the branch.

### Medium (8)

**F03 — No CI run exists for the reviewed commit, and the branch is not pushed.** `gh run list` returns runs only for `7ddfc63` and `c271fe3`; `git ls-remote origin` lists only `refs/heads/main`. The delta `7ddfc63..03435fb` is `FIX_REPORT_04.md` and `review-state.json` — documentation, hence Medium rather than High — but the state being handed over has itself never been through the pipeline. Fix: push the branch and record a run at the handed-over commit.

**F04 — `merge-gate` is not a required status check.** Protection requires eleven contexts; `merge-gate` is not among them, and `ci.yml:215` restricts it to `pull_request`. `reports/negative-prs/pr-*-checks.json` shows `merge-gate: FAILURE` on all five negative PRs that were merged. M00-11 AC8's checklist is therefore executed but unenforced. Fix: add `merge-gate` to the required contexts.

**F05 — `AcceptanceMapping` accepts a criterion when any one quoted token resolves.** `lib/gates/acceptance_mapping.rb:68` — `text.scan(QUOTED).flatten.any? { … }` — with `named_in_code?` (`:84-89`) accepting any ≥6-character string containing three letters found anywhere in a corpus spanning `spec/**`, `app/**`, `lib/**`, `bin/*`, `config/**`, `db/**`, `.github/**`. A criterion with one real reference and four invented ones passes. Fix: require every quoted reference in the evidence cell to resolve.

**F06 — `bin/merge-gate`'s `ci_green` ignores provenance.** `bin/merge-gate:149` reads only `JSON.parse(File.read(path))["result"]`, while `bin/_gate_lib.sh:139-171` records `commit`, `branch` and `dirty` in every result, with a comment explaining exactly why. `lib/gates/post_commit.rb:176-181` enforces the same field correctly. A result from another commit, another branch or a dirty tree satisfies the merge gate. Fix: reject results whose `commit` is not HEAD or whose `dirty` is true.

**F07 — `pipeline_change_authorised` attributes authorisation to a commit range.** `bin/merge-gate:292-301` scans `git log --format=%s%n%b "$base...HEAD"` for any `M\d\d-\d\d`/`ADR-\d{4}` token, so a pipeline change passes whenever any unrelated commit in the range names a Story. `spec/gates/ci_pipeline_spec.rb:414-421` "tests" it by grepping `bin/merge-gate`'s own source for constant names. Fix: attribute authorisation to the commit that touched the pipeline path, and test against planted diffs.

**F08 — AF-02's Tier-0 boundary was widened without the ADR the file demands.** `config/architecture/fitness.yml:51-56` lists three paths beyond `app/executors/`; the same file states that adding a path there "is a Tier-0 security change … It needs an ADR, not a Story". `docs/decisions/` contains no such ADR. Fix: write it or narrow the list.

**F09 — The eighteen Story self-reviews predate the code they certify.** `git log -1` on each file under `docs/implementation/M00/review/` returns 2026-09-06 and one of `b770cb0 f735d9f 35f1b9a 87850bd 6dc688c 0b0465b 2a38d11`; roughly thirty commits have since rewritten `bin/redact-artifacts`, `bin/setup`, `config/security/gitleaks.toml`, `lib/gates/swarm_lab.rb` and several specs. The Exit Gate's "Critical = 0 e High = 0 no review de todas as Stories" is met by reviews of superseded code. Fix: add a per-round self-review or refresh the eighteen.

**F10 — The loop's state file is not produced solely by its owner.** `tools/opanel-loop/scripts/review-state.sh:43-47` writes `maxReviewAttempts`/`maxFixAttempts` only in `cmd_init`, both `3`, and offers no command to change them; `docs/implementation/M00/review-state.json` carries `5`/`5`, raised by hand in `ca7f2a3`, `4b357cf` and `35be86e`. `FIX_REPORT_04.md:30-37` additionally records `fixAttempt` moving 4→5 with no `fix-start` issued and no explanation. `CLAUDE.md` states the script "owns those transitions". Fix: give `review-state.sh` an explicit, recorded budget command and reconcile the counters.

### Low (2)

**F11 — `pr-gate` evaluates one aggregate, not the named jobs.** `.github/workflows/ci.yml:183-205` claims "this check requires every named job — 'nothing red' is not the condition", but `needs: [pr-stage]` yields a single matrix aggregate. Removing a job from the matrix would not fail `pr-gate`. Mitigated in practice because the eight job names are individually required contexts. Fix: correct the comment or list the jobs.

**F12 — Two comments overstate what the CI job runs.** `bin/gate:202` and `bin/security:101` say the `security-fast` job "scans the whole tree and the history", while `config/ci/jobs.yml:66` invokes `bin/security --out …` without `--history`; the history scan reaches CI only through the `controls` command. Fix: add the flag or narrow the comment.

## 10. Required Fixes

1. Deliver M00-11's negative Required Test against the now-enforced checks — five pull requests, one per class, left unmerged with their failing checks visible — or replace the criterion by Story/ADR and correct `tasks.json`. (F01)
2. Regenerate `MILESTONE_REPORT.md` against the handed-over commit: the fifteen criteria with commands and exit codes, the CI run id, the incident, the public-repository trade, all open Mediums; and make `StopGate#milestone_report` require HEAD and branch. (F02)
3. Push the branch and record a pipeline run at the commit being handed over. (F03)
4. Add `merge-gate` to the required status checks. (F04)
5. Harden the three gates that accept shape: every quoted reference must resolve; `ci_green` must reject stale or dirty provenance; `pipeline_change_authorised` must attribute to the commit that changed the pipeline, and be tested. (F05, F06, F07)
6. Write the Tier-0 ADR for `docker_boundaries` or narrow it; refresh the self-reviews; move the budgets behind an explicit `review-state.sh` command. (F08, F09, F10)

## 11. Evidence

Read: `CLAUDE.md`, `docs/AGENT_RULES.md`, `docs/goals/REVIEW_MILESTONE.md`; `docs/implementation/M00/{README.md,GOAL.md,tasks.json,review-state.json,MILESTONE_REPORT.md,FIX_REPORT_04.md,MILESTONE_REVIEW_04.md}`; `stories/M00-11-ci-pipeline-and-gates.md`; `reports/M00-11.md`; `reports/negative-prs/{README.md,pr-11.json,pr-11-checks.json}`; the eighteen files under `review/`; `.github/workflows/ci.yml`; `config/ci/jobs.yml`, `config/architecture/fitness.yml`, `config/security/gitleaks.toml`; `bin/{gate,merge-gate,security,_gate_lib.sh}`; `lib/gates/{acceptance_mapping,post_commit,stop_gate,fitness_functions}.rb`; `lib/opanel/{correlation_middleware,configuration}.rb`; `spec/gates/{ci_pipeline,fitness_functions}_spec.rb`; `app/frontend/components/INVENTORY.md`; `docs/templates/`; `tools/opanel-loop/scripts/review-state.sh`.

Read-only commands: `git log/show/status/branch/ls-remote/grep/rev-list/fsck`; `gh run list`, `gh run view --json`, `gh api repos/DouglasPrado/opanel`, `.../branches/main/protection`, `.../pulls/{5,7,9,10,11,12,13}`, `.../commits/{f797866c805a,972c76a62309,ea19516f7e03}`. Nothing in the workspace was modified; `git status` still shows only the pre-existing modification to `docs/implementation/M00/review-state.json` made by the runner.

## 12. Final Recommendation

Hold M00 at **NOT_ACCEPTED**, and note what that does *not* mean. The security incident is closed on the merits — the object is gone from the server, the branch is protected, and the incident is written down in the pack instead of being left for a reviewer to discover. That is three of four blocking findings answered in acts rather than prose, and it was done under an exhausted fix budget with the awkward parts declared rather than dressed up.

What remains is proof, in the two places the Milestone chose as its own definition of proof. M00-11 asks for five pull requests demonstrably blocked; what exists is a JSON file describing five pull requests that were merged, pointing at objects that now return 404 and 422. And the Milestone Report — the one artefact a human reads before accepting — describes a different commit on a different branch and says no independent review has happened. Both are days of work away from being closed, not weeks, and the machinery to close them is already built and enforced. With the fix budget at 5 of 5, this should go to a human decision rather than another automated round.

---

## Counts

| Severity | Count | Findings |
|---|---|---|
| Critical | 0 | — |
| High | 2 | F01, F02 |
| Medium | 8 | F03, F04, F05, F06, F07, F08, F09, F10 |
| Low | 2 | F11, F12 |

Verdict: **NOT_ACCEPTED**
