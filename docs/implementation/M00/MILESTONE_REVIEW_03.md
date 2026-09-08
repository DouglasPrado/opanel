# Milestone Review M00 — Attempt 03

- Reviewer role: Claude independent (read-only)
- Attempt: 03
- HEAD: b9aa4122acf802444217b8285722beaa4746a4fa
- Branch: loop/replace-orchestrator
- Verdict: NOT_ACCEPTED
- Counts: Critical 0 · High 3 · Medium 6 · Low 2

Coherence check performed by the orchestrator before recording: each severity
count equals the number of findings at that severity (11 findings total);
NOT_ACCEPTED carries three High findings; every finding names a file that exists
and evidence located in the repository at this HEAD.

---

# Independent Milestone Review — M00 Foundation, Attempt 03

Reviewer: independent Milestone reviewer (read-only)
Target: `b9aa4122acf802444217b8285722beaa4746a4fa` on `loop/replace-orchestrator`
Method: reading only. No suite, gate, or CI job was executed; no file was written.

## 1. Verdict

**NOT_ACCEPTED — Critical: 0 · High: 3 · Medium: 6 · Low: 2.**

## 2. Executive Summary

The engineering substance of M00 is real and, in most places, better than its reports claim. The ten findings of `CODEX_REVIEW_02.md` are genuinely answered in code at this HEAD: `lib/gates/swarm_lab.rb` now resolves the endpoint through the CLI's own precedence and matches by scheme and exact host with a loopback resolution check before opening any connection; `orphaned_resources` raises `InventoryUnknown` and `bin/swarm-lab down` refuses before `swarm leave --force`; `bin/_gate_lib.sh:39` uses `mktemp "${TMPDIR:-/tmp}/opanel-gate.XXXXXXXX"` with a stand-in GNU `mktemp` in the spec that rejects the old form; `lib/gates/post_commit.rb#covered_suites` credits nothing for a narrowed run and refuses skips; AF-06 reads the whole call expression and AF-07 requires the Policy to be constructed *and* the predicate invoked; `bin/merge-gate` reads `tmp/security/security-report.json` and the Markdown reviews. Each carries a negative test that would fail if the defect returned. I verified these by reading the code, not by trusting the fix report.

What blocks acceptance is not those fixes. It is three things the fixes did not reach.

First, **the CI pipeline this Milestone delivers has never run**. `docs/implementation/M00/stories/M00-11-ci-pipeline-and-gates.md:59` declares its Required Tests as "execução completa do pipeline em branch de teste, verde" and "cinco PRs de teste, um por classe de falha (2–6), cada um comprovadamente bloqueado". Neither happened. `loop/replace-orchestrator` has never been pushed; `origin/docs/agent-bootstrap` carries the work but its pull request (#1, merged at `e6fd069`) predates every implementation commit, and `.github/workflows/ci.yml:24-28` triggers only on `pull_request`, `push: branches: [main]` and `workflow_dispatch`. Every number in the reports comes from `bin/ci-job` on a developer laptop. The M00-R18 `mktemp` defect — which would have killed `gate_begin` on every Ubuntu runner, on every gate, on every push — is the proof that local and CI are materially different environments, and it was found by reading, two review rounds in, not by running.

Second, **two required Stories record test evidence that cannot have happened**. `reports/M00-06.md` lists `spec/integration/setup_spec.rb` and `spec/integration/dev_supervisor_spec.rb` as files it changed and records `bundle exec rspec` over both as "green"; `reports/M00-15.md:57` records `bundle exec rspec spec/integration/health_spec.rb` as "green, including PostgreSQL stopped". `git log --all` for all three paths returns nothing — they have never existed on any branch. `FIX_REPORT_02.md:270-272` found one of these while fixing M00-R07 and corrected only the criterion the acceptance gate reads, leaving the same fabrication in two other tables of the same report. That is a fix fitted to the check rather than to the problem.

Third, **the governance under which this verdict is produced was replaced on this branch without the record AGENT_RULES requires**. Commit `4d2fb44` introduced `tools/opanel-loop/`, whose `agents/milestone-reviewer.md` makes a Claude subagent the independent Milestone reviewer and whose `scripts/review-state.sh` writes `reviewing`, `fix_required` and `human_acceptance`. `CLAUDE.md` at this HEAD forbids exactly that, item by item, and `ADR-0003` is still `status: "accepted"` describing the orchestrator that was moved to `scripts/legacy/`. No superseding ADR exists and `SPEC_CONFLICTS.md` records nothing.

Beyond the blockers, the accounting in `MILESTONE_REPORT.md` does not reconcile with the eighteen self-reviews it summarises, and those self-reviews were all last written at `2a38d11` — before roughly twenty commits rewrote the code they judge.

## 3. Story Coverage Matrix

`PASS` means implemented, tested and accounted for. `PARTIAL` means the work is present but a declared obligation is not proved. `FAIL` means a Required Test or Definition of Done item is unmet. The Tests column describes inspection of the specs, not execution.

| Story | Implementation | Tests | Acceptance Criteria | Result |
|---|---|---|---|---|
| M00-01 | Single Rails 8.1 app, boundary directories, no domain entity | 20-example baseline; `spec/architecture/repository_layout_spec.rb` | Criteria map to real files | PASS |
| M00-02 | PostgreSQL, checkpoint table, Migration Gate, reversibility | `spec/integration/database_spec.rb`, `spec/gates/migration_gate_spec.rb` with planted violations | Met; ADR-0002 deferral is legitimate | PASS |
| M00-03 | Solid Queue, six queues, retry classes, idempotent example job | `spec/integration/jobs_spec.rb`, `worker_crash_spec.rb` | Met; `async` on Darwin is a disclosed Medium | PASS |
| M00-04 | Inertia + React + TS + Vite + Tailwind, CSRF, error page | `spec/requests/inertia_spec.rb`, `root_spec.rb`, `e2e/smoke.spec.ts` | Met | PASS |
| M00-05 | 52 components imported, `INVENTORY.md`, gallery, registry | `spec/frontend/component_inventory_spec.rb`, `registry.test.tsx` (53 tests) | Met; two strictness flags dropped, disclosed | PASS |
| M00-06 | `bin/setup`, `bin/dev`, seeds, README single command | `spec/integration/development_environment_spec.rb` — real; the two specs the report names do not exist | AC table correct; **recorded test evidence false** (F02) | PARTIAL |
| M00-07 | RSpec + FactoryBot on real PostgreSQL, parallel databases, clock, namespaces | `spec/integration/test_harness_spec.rb`, concurrency helpers | Met | PASS |
| M00-08 | Vitest, Playwright, masked capture, artifact redaction with trace rewriting | `spec/security/artifact_redaction_spec.rb` (20 examples), `e2e/support/masked-capture.ts` | Met; `style-src 'unsafe-inline'` disclosed | PASS |
| M00-09 | RuboCop + ESLint + Prettier + tsc, custom cops, Suppression Gate | `spec/gates/lint_rules_spec.rb` with planted violations | Met | PASS |
| M00-10 | gitleaks, bundler-audit, npm audit, Brakeman, per-vulnerability report, Dependency Gate | `spec/security/security_scan_spec.rb` (49 examples) incl. history scan | Met | PASS |
| M00-11 | `config/ci/jobs.yml`, `bin/ci-job`, workflows, Merge Gate, flaky-rate | `spec/gates/ci_pipeline_spec.rb` simulates the five failure classes locally | **Required Tests unmet**: no green pipeline run on a branch, no five blocked PRs, archive action never executed (AC9) (F01) | FAIL |
| M00-12 | `bin/gate` local/pre-commit/post-commit, hook, evidence certificate | `spec/gates/gate_scripts_spec.rb` (68 examples), GNU `mktemp` stand-in | Met, but the Story's own rule "nenhuma Story pode ser declarada `done` sem CI verde" (M00-11 §Quality Gates) is unsatisfied; acceptance verifier is shape-tolerant (F07) | PARTIAL |
| M00-13 | AF-01..AF-10, waivers with human-approval class, metadata in config | `spec/gates/fitness_functions_spec.rb` — a positive and a negative per function, verified | Met | PASS |
| M00-14 | Pack schema, validator, `bin/pack`, Stop Gate, directory contracts | `spec/gates/pack_spec.rb`, `stop_gate_spec.rb` | Substantively met, but AC1 and AC8 name `config/schemas/tasks.schema.json`, which has never existed (actual: `config/pack/tasks.schema.json`) and passes the gate anyway (F07) | PARTIAL |
| M00-15 | `LogFormatter`, `Redaction`, correlation middleware, `/up` with classified causes | `spec/integration/observability_spec.rb`, `job_correlation_spec.rb`, `spec/requests/health_spec.rb` | AC table correct; **recorded test evidence false** (F02) | PARTIAL |
| M00-16 | Typed `Configuration`, fail-closed boot with `EX_CONFIG`, workspace guardrail | `spec/unit/configuration_spec.rb`, `spec/integration/boot_configuration_spec.rb` | Met | PASS |
| M00-17 | Endpoint resolution, exact-host allowlist, `InventoryUnknown`, idempotent up/down | `spec/integration/swarm_lab_spec.rb` (36+ examples incl. context and loopback negatives) | Met, but the Tier-0 `docker_boundaries` widening has no ADR, which `fitness.yml` itself requires (F09) | PARTIAL |
| M00-18 | ADR, Story Report, Milestone Report, Review Findings, Blocker templates | `spec/documentation/templates_spec.rb` | Met | PASS |

**Milestone-level criteria (`README.md` §Acceptance Criteria).** 1–8, 10–15 are satisfiable from the repository. **AC9** ("O CI reprova um PR com typecheck, lint, teste ou secret scan falhando") is proved only by local simulation. The **Exit Gate** item "o pipeline de CI está verde em uma execução completa do branch" (`README.md:145`) is unmet.

## 4. Test Results

No suite was executed by this review. Every figure below is a claim read against the repository.

| Claim | Source | Verification |
|---|---|---|
| `bin/test` — 723 examples, 0 failures, `complete: true`, `skipped: 0`, `dirty: false` at `9cdba23` | `FIX_REPORT_02.md:847` | **Not reconstructible.** `tmp/` is gitignored (`.gitignore:30`, `:47`). The metadata now on disk reads `"scope": "changed"`, `"fast": true`, `"complete": false`, `"tests": 609`, `"commit": "44a0c64…"`, `"dirty": true` — a later, narrower run has overwritten it. |
| 10/10 `required_for_merge` CI jobs PASS at `ca7f2a3` | `FIX_REPORT_02.md:767-778` | The on-disk `tmp/ci-results/*.json` do name `commit: ca7f2a3…`, which is real and checkable — but they are untracked and describe a commit two behind HEAD. |
| Security report `counts: {critical: 0, high: 0}` | `tmp/security/security-report.json` | Present, generated at `9cdba23`, consistent with the empty `tmp/security/scanners/*.json`. Untracked. |
| 307 examples across the seven changed spec files | `FIX_REPORT_02.md:702` | Consistent with the files: `gate_scripts_spec.rb` 68, `fitness_functions_spec.rb` 47, `security_scan_spec.rb` 49, `ci_pipeline_spec.rb` 36, `swarm_lab_spec.rb` 36, `artifact_redaction_spec.rb` 20, `stop_gate_spec.rb` 21 top-level examples plus shared groups. Plausible; not verifiable exactly without running. |
| Five negative PR classes proved | `FIX_REPORT_02.md:542-554` | The five examples exist in `spec/gates/ci_pipeline_spec.rb` and plant real failures against `bin/ci-job`. They are **not** the five pull requests `M00-11` Required Tests demands. |
| M00-06 and M00-15 spec runs "green" | `reports/M00-06.md`, `reports/M00-15.md:57` | **False.** `git log --all -- spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb spec/integration/health_spec.rb` returns nothing. |

**Test quality.** The negatives are, on the whole, honest. `spec/gates/gate_scripts_spec.rb:78` asserts that the GNU `mktemp` stand-in *rejects* the old form, so the portability test cannot pass for the wrong reason; `spec/gates/fitness_functions_spec.rb:432-471` proves three inert mentions of a Policy are refused *and* that a two-line invocation is still accepted, so AF-07 is not passing by refusing everything; `spec/security/security_scan_spec.rb:135` blocks a real advisory against `rack 2.0.1` rather than a stub. Two limits worth naming: `spec/integration/job_correlation_spec.rb:36` sets `Current` by hand after the request rather than having the request enqueue the job, so the HTTP→worker-log path is proved in two halves (`observability_spec.rb:59` covers the log half in-process); and `spec/integration/development_environment_spec.rb` reads `bin/dev` structurally rather than killing a child of a live supervisor — a gap the Story report now discloses.

`spec/policies/` and `spec/contracts/` contain only a README. That is honest for M00 and correctly declared.

## 5. Quality Gate Results

Read, not run. What each gate actually executes, against what the reports claim it proves:

| Gate | What the script does | Assessment |
|---|---|---|
| `bin/gate local` | format, lint, typecheck, `bin/test --changed`, `frontend-tests` (or explicit skip), migrations, contracts, security, fitness — nine reported checks | Matches the claim. `frontend_changed` (`bin/gate:70-74`) closes the M00-R06 gap. |
| `bin/gate pre-commit` | the eight names of Annex I §12.1 in order; `record_pre_commit_evidence` returns early when `GATE_FAILURES != 0` | Matches. The certificate is keyed by `git write-tree` and names the checks, so `post_commit.rb:317` can compare against `PRE_COMMIT_CHECKS`. |
| `bin/gate post-commit` | eight checks via `lib/gates/post_commit.rb` plus `check_no_verify_absent` | Matches. `tests` refuses evidence from another commit, with zero examples, with failures, with skips, or narrower than the Story's declared suites. At HEAD this check would currently be **red**: the metadata on disk names `44a0c64`, not `b9aa412`, and `complete: false`. |
| `bin/fitness` | ten checkers, each reported with id, rule, status, duration, violations | Matches. Waivers require owner, deadline, removal Story and — for AF-02/06/07 — `approved_by`. |
| `bin/pack validate` | schema first, then semantic rules | Matches; 15 `tasks.json` files exist. |
| `bin/stop-gate` | ten checks, each executing a command; `milestone-report` requires eight non-empty sections | The report check verifies **section presence**, not that the report describes this commit — which is how `MILESTONE_REPORT.md` passes while naming `Head: f32a344` on a different branch (F05). |
| `bin/security` | waivers, allowlist, gitleaks, dependency gate, bundler-audit, npm audit, Brakeman; each scanner's machine-readable output kept and parsed per vulnerability | Matches, and `unreadable`/`unmeasured` make a missing scanner result a High finding rather than silence. But `--history` is passed by no CI job — only by `spec/security/security_scan_spec.rb:120` (F10). |
| `bin/merge-gate` | ten checks; reads `config/ci/jobs.yml#required_for_merge` by name, `tmp/security/security-report.json#counts`, and the Markdown reviews | The M00-R17 fix is real. **`ci_green` (`bin/merge-gate:137-160`) reads only `result`** and ignores the `commit`, `branch` and `dirty` fields `gate_write_json` writes — so a result from another commit or a dirty tree satisfies it (F08). |
| `bin/ci-job` / `.github/workflows/ci.yml` | the workflow only schedules; `jobs.yml` is the definition | Sound design. **Never executed** (F01). |
| Acceptance mapping | `verifiable?` succeeds if **any** backticked token in the evidence cell is an existing path or a ≥6-character string found anywhere in a large source corpus | Accepts the shape of evidence. Demonstrated by `reports/M00-14.md:65,72` (F07). |

## 6. Architecture Review

The approved stack is intact: Rails 8.1.x, PostgreSQL, Solid Queue, Inertia + React + TypeScript over Vite and Tailwind. No Next.js, no HTMX, no second frontend. No domain entity was implemented early — `config/architecture/fitness.yml` correctly ships `user_intent_columns: []` and `critical_mutations: []` rather than inventing them.

Boundaries hold. No controller, job or model references Docker; `app/controllers/gallery_controller.rb` is routed only under `Rails.env.development? || Rails.env.test?` (`config/routes.rb:11`). `HealthController` inherits `ActionController::Base` deliberately and leaks no version, host or connection string. `ApplicationController`'s `inertia_share` carries only `requestId` and flash. There is no speculative abstraction: no generic repository, no event bus, no plugin system.

Two architecture-level concerns:

- **AF-02's Tier-0 list has been widened without the ADR it declares.** `config/architecture/fitness.yml` states, in its own header, "**Adding a path here is a Tier-0 security change** (Annex C §8). It needs an ADR, not a Story," and then adds three entries — `spec/support/swarm_lab`, `bin/swarm-lab`, `lib/gates/swarm_lab.rb`. `docs/decisions/` contains no such ADR. The substance is defensible (the entries are test and gate tooling, no route, no application caller) and it is disclosed as `M00-17 F-2`; the required artifact is simply absent (F09).
- **The review-independence model was changed without an ADR.** `ADR-0003` is `status: "accepted"` and describes a Bash orchestrator with Codex as the independent reviewer. `4d2fb44` moved that orchestrator to `scripts/legacy/` and replaced it with `tools/opanel-loop/`. AGENT_RULES requires "a permanent exception to an existing invariant" to become an ADR *before* it becomes an implicit pattern (F03).

## 7. Security Review

Concrete controls, verified by reading:

- **Fail-closed configuration.** `lib/opanel/configuration.rb` declares every key with its required environments and format, never defaults a credential, exits `EX_CONFIG` (78) before the application class is defined, and `problem_for` never echoes the received value.
- **Redaction at the sink.** `Opanel::LogFormatter#call` applies `Redaction.apply` to the whole payload and its fallback path applies it again; `spec/integration/observability_spec.rb:136-152` plants a token and an Authorization header and asserts neither survives.
- **Artifact sanitisation.** `bin/redact-artifacts` splits `VISUAL` from `INERT_OPAQUE`, publishes a visual artifact only when its digest appears in the capture manifest written by `e2e/support/masked-capture.ts`, covers visual entries inside archives with a 70-byte placeholder and rewrites the archive, and deletes anything it cannot inspect. `.github/actions/archive/action.yml` runs it *before* the upload. This is a genuine answer to M00-R02.
- **Lab guardrail.** `assert_claimable_endpoint!` runs before any connection; `tcp` hosts must match exactly *and* resolve exclusively to loopback (`loopback?`, `lib/gates/swarm_lab.rb:207-214`), so `tcp://localhost.attacker.example` and `tcp://127.0.0.1.example.com` are refused; there is no environment variable that skips the check.
- **Secret scanning.** `config/security/gitleaks.toml` allowlists fixture values one by one with reasons rather than allowlisting `spec/security/`, and `spec/security/security_scan_spec.rb:110-117` asserts `docs/implementation`, `reports` and `evidence` are *not* allowlisted. Nothing under `tmp/` is tracked (`git ls-files tmp/` returns only two `.keep` files).

Two security-relevant gaps, neither a live vulnerability in M00 (there is no authentication, tenancy or secret store yet, correctly deferred to M01/M11):

- The history secret scan is exercised only by a spec, while `bin/security:101-102` and `bin/gate:202-203` both assert in comments that CI scans the history. No CI job passes `--history` (F10). Milestone AC14 survives because `bin/test --type security` runs inside the `security-fast` job, but the stated mechanism is wrong.
- Because CI has never run, the `security-fast` job's gitleaks install, the whole-tree scan on a runner with `fetch-depth: 0`, and the artifact redaction step have never executed anywhere.

## 8. Scope Review

**Missing scope.** M00-11's Required Tests (a green pipeline run on a branch; five blocked PRs) and Exit Gate item "CI verde em uma execução completa do branch" are not delivered.

**Scope creep.** `4d2fb44` adds ~1,800 lines under `tools/opanel-loop/` plus edits to `.claude/settings.json`, `AGENTS.md`, `docs/goals/FIX_REVIEW_FINDINGS.md` and `docs/implementation/AGENT_ORCHESTRATOR.md`. No Story owns it, no boundary in `boundaries.yml` covers it, and `bin/merge-gate`'s `pipeline-change-authorised` does not see it because `PIPELINE_PATHS` contains no `tools/` or `.claude/` prefix. `CLAUDE.md` forbids the implementer from modifying "the orchestrator, its runners, schemas, hook or review/fix role prompts while executing a Milestone or fixing review findings" — the Milestone was in `blocked`/`fix_required` at the time.

**Overengineering.** None found. The gate library is large but every piece has a caller and a negative test; the empty fitness metadata lists and the declared-empty `policy`/`contract` suites are the correct minimum rather than speculative structure.

**Retry budget.** `maxReviewAttempts` was raised 3→4 in `4d2fb44` and `maxFixAttempts` 3→4 in `ca7f2a3`, both by direct edit of `review-state.json`. `tools/opanel-loop/scripts/review-state.sh` — declared "the only writer" of that file — exposes no command to change either. The rationale (execution failures are not verdicts) is recorded in the commit messages and is defensible; the mechanism is not (F11).

## 9. Findings by Severity

### Critical

None.

### High

**F01 — The CI pipeline the Milestone delivers has never executed, and M00-11's Required Tests are unmet.**
`docs/implementation/M00/stories/M00-11-ci-pipeline-and-gates.md:59-60` declares: "**integration**: execução completa do pipeline em branch de teste, verde" and "**negativo**: cinco PRs de teste, um por classe de falha (2–6), cada um comprovadamente bloqueado". `README.md:145` repeats it as an Exit Gate item. Neither exists. `git branch -a` shows `loop/replace-orchestrator` only locally; `git rev-list --count origin/main..HEAD` is 64 and `HEAD..origin/main` is 1 (`e6fd069`, the merge of PR #1, which the branch does not contain and which predates every implementation commit). `.github/workflows/ci.yml:24-28` triggers on `pull_request`, `push: branches: [main]` and `workflow_dispatch` — none of which a push to `docs/agent-bootstrap` with no open PR satisfies. `FIX_REPORT_02.md:556-559` explicitly declines the five PRs. Consequently AC9 of the Milestone, AC2–AC6 and AC9 of M00-11, the `.github/actions/setup` composite action, the gitleaks install step, the postgres service wiring, the `docker pull` of the lab image, `actions/download-artifact@v4` and the `merge-gate` job have never been exercised. M00-11 also states "A partir daqui, nenhuma Story pode ser declarada `done` sem CI verde" — seven Stories were closed after it without one. That the M00-R18 `mktemp` defect would have aborted every gate on every Ubuntu runner, and survived two review rounds undetected by any local run, is the demonstration that this gap is not formal.

**F02 — Two required Stories record test runs against spec files that have never existed.**
`docs/implementation/M00/reports/M00-06.md` lists, under "Arquivos alterados", "`spec/integration/setup_spec.rb`, `spec/integration/dev_supervisor_spec.rb` | The harness, proven", and under "Testes executados", "`bundle exec rspec spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb` | green". `docs/implementation/M00/reports/M00-15.md:21` and `:57` do the same for `spec/integration/health_spec.rb`, recorded as "green, including PostgreSQL stopped". `git log --oneline --all -- spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb spec/integration/health_spec.rb` returns nothing: none has ever existed on any branch. The real specs are `spec/integration/development_environment_spec.rb` (added at `b8a5f82`) and `spec/requests/health_spec.rb` (added at `524e9ed`). `FIX_REPORT_02.md:270-272` records finding one of these ("M00-06 #3 cited `spec/integration/dev_supervisor_spec.rb`, which does not exist") and corrected only the Acceptance Criteria row the gate reads, leaving the identical claim in two other tables of the same file. Definition of Done for both Stories rests on evidence that is demonstrably false as written.

**F03 — The accepted review-orchestration decision was superseded without an ADR, and `CLAUDE.md` at HEAD forbids what the replacement does.**
`docs/decisions/ADR-0003-agent-review-orchestrator.md` is `status: "accepted"` and specifies the Bash orchestrator with Codex as independent reviewer. Commit `4d2fb44` moved it to `scripts/legacy/` and introduced `tools/opanel-loop/`, whose `agents/milestone-reviewer.md` declares a Claude subagent as "the independent reviewer of an entire Milestone", and whose `scripts/review-state.sh:88` sets `.status = "reviewing" | .lastReviewer = "claude"` and `:109` routes an accepted verdict to `human_acceptance`. `CLAUDE.md` at this HEAD (unchanged since `298286d`) states: "Claude is never the independent Milestone reviewer. It must not: … set `review-state.json` to `reviewing`, `fix_required`, `accepted` or `human_acceptance`; replace the Codex review with a subagent, fresh Claude context or self-review; modify the orchestrator, its runners, schemas, hook or review/fix role prompts while executing a Milestone or fixing review findings." `AGENTS.md:9` still reads "Codex is the independent **REVIEWER** for completed Milestones." `docs/decisions/` contains no ADR-0004 and `docs/implementation/SPEC_CONFLICTS.md` has no entry for this. AGENT_RULES requires a systemic decision — "a security-boundary change, or a permanent exception to an existing invariant" — to become an ADR before it becomes an implicit pattern, and requires an unrecorded conflict to be recorded rather than resolved silently. The mechanism is well built; the record is missing, and the missing record governs the acceptance of this Milestone.

### Medium

**F04 — `MILESTONE_REPORT.md` understates the open findings a human is asked to accept.**
Its Findings table records "Medium | 6 | 11" and enumerates exactly six open Mediums (M00-17 F-2, M00-12 F-1, M00-08 F-2, M00-05 F-2, M00-05 F-3, M00-03 F-1). A seventh exists: `docs/implementation/M00/review/M00-09.md` F-3, "Six ESLint rules are off for the imported component tree", `- **Severidade:** Medium`, `- **Estado:** open, resolved by fixing the library upstream`, counted in that review's own table as "Medium | 1 (F-3, owned upstream)". Three of those six rules are accessibility rules. The Low count is worse: the report claims 12 open, while summing the eighteen reviews' own "Abertos" figures gives roughly 22 (and `review/M00-12.md:74` claims "Low 3" against two Low findings in its own body). The report is the artifact the human acceptance gate reads.

**F05 — `MILESTONE_REPORT.md` describes a different commit on a different branch, and the Stop Gate cannot tell.**
Lines 6-8 record `Branch: docs/agent-bootstrap`, `Head: f32a344`, and the Quality table records "`bin/test` … 554 examples". HEAD is `b9aa412` on `loop/replace-orchestrator`, and the suite is 723 examples after two rounds of fixes. The staleness is disclosed in a note, but `lib/gates/stop_gate.rb:228-249` checks only that eight named headings exist with more than three characters under them — so a report about an entirely different state passes `milestone-report`. The one check whose job is to stop a Milestone being handed over without an account of itself accepts an account of something else.

**F06 — The eighteen implementation self-reviews predate the code they certify.**
Every file under `docs/implementation/M00/review/` was last written at `2a38d11` (2026-09-06) or earlier; roughly twenty subsequent commits rewrote the code. `review/M00-17.md:3` records "Reviewed diff: `0214fb4..f230511`" and line 11 "no finding — 15 examples against a real Engine", while `fa0429d` rewrote `lib/gates/swarm_lab.rb`'s endpoint resolution, allowlist matching and inventory semantics, and `spec/integration/swarm_lab_spec.rb` now holds 36 top-level examples. The Exit Gate condition "Critical = 0 e High = 0 no review de todas as Stories" is satisfied by reviews of superseded code.

**F07 — The acceptance-mapping verifier accepts the shape of evidence.**
`lib/gates/acceptance_mapping.rb:68` — `text.scan(QUOTED).flatten.any? { |token| path?(token) || named_in_code?(token) }` — is satisfied by **any one** backticked token in the cell, and `named_in_code?` (`:84-89`) accepts any string of six or more characters containing three letters that appears anywhere in a corpus spanning `spec/**`, `app/**`, `lib/**`, `bin/*`, `config/**`, `db/**`, `.github/**` and `package.json`. Demonstrated live: `reports/M00-14.md:65` and `:72` both cite `config/schemas/tasks.schema.json` as the artifact satisfying AC1 and AC8. That path has never existed (`git log --all` is empty for it; the schema is at `config/pack/tasks.schema.json`). Both criteria pass because another token in the same cell resolves. The M00-R07 fix moved the bar from "the author ticked a box" to "the author quoted something that exists somewhere" — real progress, but not "the evidence proves the criterion".

**F08 — `bin/merge-gate`'s `ci_green` ignores the provenance fields the M00-R19 fix added.**
`bin/_gate_lib.sh:138-177` records `commit`, `branch` and `dirty` in every gate result precisely so "an archived result names the code it describes". `bin/merge-gate:149` then reads `JSON.parse(File.read(path))["result"]` and nothing else. A `tmp/ci-results/<job>.json` from any commit, any branch, or a dirty tree satisfies the check. The current on-disk results illustrate it: all ten name `commit: ca7f2a37d…` and `dirty: true`, two commits behind HEAD, and `ci_green` would pass on them today.

**F09 — AF-02's Tier-0 boundary was widened without the ADR the file itself requires.**
`config/architecture/fitness.yml` states "**Adding a path here is a Tier-0 security change** (Annex C §8). It needs an ADR, not a Story," and its `docker_boundaries` list then contains `spec/support/swarm_lab`, `bin/swarm-lab` and `lib/gates/swarm_lab.rb` alongside `app/executors/`. `docs/decisions/` holds ADR-0001, ADR-0002 and ADR-0003 and nothing on this. `review/M00-17.md` F-2 discloses the change as Medium and names a stopping point ("if M01's executor Story finds itself adding a fourth entry"), but the process the control mandates for itself was not followed.

### Low

**F10 — Two gate scripts assert a CI behaviour that no CI job performs.**
`bin/security:101-102`: "**CI always scans the whole tree and the history**: the scope moves, the check does not." `bin/gate:202-203`: "the `security-fast` CI job scans the whole tree and the history." `config/ci/jobs.yml:64` runs `bin/security --out tmp/security/security-report.json` — no `--history`. The only invocation of `--history` in the repository is `spec/security/security_scan_spec.rb:120`. Milestone AC14 is still covered, because that spec runs inside the job's `controls` command, but the stated mechanism is wrong and a reader relying on it would be misled.

**F11 — The retry budgets were raised by hand in `review-state.json`.**
`4d2fb44` raised `maxReviewAttempts` from 3 to 4; `ca7f2a3` raised `maxFixAttempts` from 3 to 4. `tools/opanel-loop/scripts/review-state.sh`, documented as "the only writer of the state" so that "the invariants are mechanical rather than remembered", offers no command that changes either field. The reasoning (an execution failure is not a verdict) is recorded in the commit messages and is sound; the budget that stops a review/fix loop was nonetheless edited by the party the loop constrains.

## 10. Required Fixes

1. **Run the pipeline.** Push the branch, open a pull request against `main`, and record a complete green run of all ten `required_for_merge` jobs together with the `merge-gate` job, tied to the reviewed commit. Then satisfy M00-11's negative Required Test by demonstrating the five failure classes blocked by the real pipeline, or open a Story/ADR that formally replaces that criterion — do not substitute local runs for it silently. (F01)
2. **Correct the false test evidence.** In `reports/M00-06.md` and `reports/M00-15.md`, replace every reference to `spec/integration/setup_spec.rb`, `spec/integration/dev_supervisor_spec.rb` and `spec/integration/health_spec.rb` with the specs that exist, and re-derive the "Testes executados" rows from a run that actually happened. Then audit the remaining sixteen reports for the same class of claim. (F02)
3. **Record the orchestration decision.** Write the ADR that supersedes ADR-0003, mark ADR-0003 superseded, update `CLAUDE.md` and `AGENTS.md` so the repository's normative instructions match the machinery in use, and add the entry to `SPEC_CONFLICTS.md`. (F03)
4. **Reconcile and refresh the Milestone Report.** List all seven open Mediums, correct the Low count, and regenerate the report against the commit being handed over rather than `f32a344`. Extend `StopGate#milestone_report` to check that the report names the current HEAD and branch. (F04, F05)
5. **Re-review the changed code.** Update the eighteen `review/*.md` files to cover the fix commits, or add a review per fix round, so `Critical = 0 / High = 0` describes the code at HEAD. (F06)
6. **Harden the two gates that accept shape.** Require an acceptance criterion's evidence to resolve in *all* of its quoted references, not one; make `ci_green` reject a result whose `commit` is not HEAD or whose `dirty` is true. (F07, F08)
7. **Write the Tier-0 ADR** for the three `docker_boundaries` entries, or narrow the list. (F09)
8. Add `--history` to the `security-fast` job or correct the two comments; move `maxReviewAttempts`/`maxFixAttempts` changes behind an explicit `review-state.sh` command with a recorded reason. (F10, F11)

## 11. Evidence

Read for this review: `CLAUDE.md`, `AGENTS.md`, `docs/AGENT_RULES.md`, `docs/goals/REVIEW_MILESTONE.md`; `docs/implementation/M00/{README.md,GOAL.md,tasks.json,review-state.json,MILESTONE_REPORT.md,boundaries.yml}`, `CODEX_REVIEW_02.md`, `FIX_REPORT_02.md`, all 18 `reports/*.md`, all 18 `review/*.md`, and the M00-11 Story; `docs/decisions/` and `docs/implementation/SPEC_CONFLICTS.md`.

Implementation read: `bin/{gate,_gate_lib.sh,test,test-metadata,security,merge-gate,swarm-lab,redact-artifacts}`; `lib/gates/{post_commit,acceptance_mapping,stop_gate,fitness_functions,swarm_lab,security_scanners,review_findings,story_boundary}.rb`; `lib/opanel/{configuration,log_formatter}.rb`; `app/controllers/{application,health}_controller.rb`; `config/routes.rb`, `config/architecture/{fitness,docker-lab}.yml`, `config/ci/jobs.yml`, `config/pack/tasks.schema.json`, `config/security/gitleaks.toml`; `.github/workflows/ci.yml` and both composite actions; `e2e/support/masked-capture.ts`; `tools/opanel-loop/{agents/milestone-reviewer.md,scripts/review-state.sh}`; `vitest.config.ts`; `.gitignore`.

Read-only commands used: `git log`, `git show --stat`, `git rev-parse`, `git status --short`, `git remote -v`, `git branch -a`, `git ls-files`, `git ls-tree`, `git rev-list --count`, `git merge-base`, `git log --all -- <path>` for existence questions, plus `ls`, `find`, `wc`, `grep` and one Ruby one-liner that read report files and tested path existence with `File.exist?`. No suite, gate, CI job or Docker command was executed. Nothing was written; the working tree still shows only the pre-existing modification to `docs/implementation/M00/review-state.json`.

Two claims I could not reconstruct and therefore did not credit: the 723-example green run at `9cdba23` with `dirty: false`, and the 10/10 CI job results at `ca7f2a3` — both live under `tmp/`, which `.gitignore:30` and `:47` exclude from the repository, and the test metadata has since been overwritten by a narrowed run at `44a0c64`.

## 12. Final Recommendation

Hold M00 at **NOT_ACCEPTED** and return the three High findings to the fixing phase. Do not advance to human acceptance and do not start M01.

The engineering is in better shape than this verdict suggests, and the reviewer should say so plainly: the ten findings of the previous round are answered in code, the negatives are real negatives, and the fail-closed instincts throughout — an unreadable inventory is not an empty lab, a missing scanner result is a High finding, an unverifiable approval is not a satisfied one — are exactly right. What is missing is proof rather than work, in the three places where proof is the whole point. A pipeline that has never run is a pipeline nobody has tested; a Story report naming a test file that has never existed is the failure mode this Milestone was built to make impossible; and a review process replaced without an ADR is the one change that cannot be judged by the process it replaced.

The next review should verify: a green pipeline run on a pull request tied to the reviewed commit, with archived per-job evidence; corrected test evidence in every Story report; and the ADR that reconciles `CLAUDE.md`, `AGENTS.md` and `ADR-0003` with `tools/opanel-loop`.

```json
{
  "milestone": "M00",
  "attempt": 3,
  "head": "b9aa4122acf802444217b8285722beaa4746a4fa",
  "branch": "loop/replace-orchestrator",
  "verdict": "NOT_ACCEPTED",
  "criticalCount": 0,
  "highCount": 3,
  "mediumCount": 6,
  "lowCount": 2,
  "findings": [
    {
      "id": "F01",
      "severity": "High",
      "story": "M00-11",
      "file": "docs/implementation/M00/stories/M00-11-ci-pipeline-and-gates.md",
      "location": "lines 59-60 (Required Tests); README.md:145 (Exit Gate); .github/workflows/ci.yml:24-28",
      "problem": "The CI pipeline delivered by M00-11 has never executed anywhere. Its Required Tests demand 'execução completa do pipeline em branch de teste, verde' and 'cinco PRs de teste, um por classe de falha (2-6), cada um comprovadamente bloqueado'; neither was performed. All reported CI results come from local bin/ci-job runs.",
      "impact": "AC9 of the Milestone and AC2-AC6 and AC9 of M00-11 are unproved, and the Exit Gate item 'o pipeline de CI está verde em uma execução completa do branch' is unmet. The composite setup action, the gitleaks install step, the postgres service wiring, the lab image pull, actions/download-artifact and the merge-gate job have never run. M00-11 also states 'A partir daqui, nenhuma Story pode ser declarada done sem CI verde' — seven Stories were closed after it without one. The M00-R18 GNU mktemp defect, which would have aborted gate_begin on every Ubuntu runner before a single check ran, survived two review rounds precisely because no CI run existed to expose it.",
      "evidence": "git branch -a lists loop/replace-orchestrator only locally; git rev-list --count origin/main..HEAD = 64 and HEAD..origin/main = 1 (e6fd069, the merge of PR #1, which the branch does not contain and which predates every implementation commit); git merge-base HEAD origin/main = 3a2e00c, a docs-only commit. .github/workflows/ci.yml triggers on 'pull_request', 'push: branches: [main]' and 'workflow_dispatch' only, so pushes to origin/docs/agent-bootstrap with no open PR triggered nothing. FIX_REPORT_02.md:556-559: 'They are not five GitHub pull requests: opening those is an outward-facing act the implementer should not take unasked'.",
      "recommendation": "Push the branch, open a pull request against main, and record a complete green run of all ten required_for_merge jobs plus merge-gate, tied to the reviewed commit, with the archived per-job evidence. Then demonstrate the five failure classes blocked by the real pipeline, or open a Story/ADR that formally replaces that criterion rather than substituting local runs for it."
    },
    {
      "id": "F02",
      "severity": "High",
      "story": "M00-06",
      "file": "docs/implementation/M00/reports/M00-06.md",
      "location": "'Arquivos alterados' table and 'Testes executados' table; same defect in docs/implementation/M00/reports/M00-15.md:21 and :57",
      "problem": "Two required Stories record test runs against spec files that have never existed in this repository, reported as green. M00-06 lists 'spec/integration/setup_spec.rb, spec/integration/dev_supervisor_spec.rb | The harness, proven' and records 'bundle exec rspec spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb | green'. M00-15 records 'bundle exec rspec spec/integration/health_spec.rb | green, including PostgreSQL stopped'.",
      "impact": "The Definition of Done for both Stories rests on evidence that could not have been produced: rspec against a non-existent path errors rather than passing. AGENT_RULES requires DONE to depend on executed checks. The underlying behaviour is in fact covered by spec/integration/development_environment_spec.rb and spec/requests/health_spec.rb, so the risk is not untested code — it is that the record a human and the gates read is false, which makes every other number in those reports suspect.",
      "evidence": "git log --oneline --all -- spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb spec/integration/health_spec.rb returns no commits: none of the three has ever existed on any branch. The real specs were added at b8a5f82 (spec/integration/development_environment_spec.rb) and 524e9ed (spec/requests/health_spec.rb). FIX_REPORT_02.md:270-272 records discovering one of these ('M00-06 #3 cited spec/integration/dev_supervisor_spec.rb, which does not exist') and corrected only the Acceptance Criteria row that lib/gates/acceptance_mapping.rb reads, leaving the identical false claim in two other tables of the same file.",
      "recommendation": "Replace every reference to the three non-existent specs with the files that exist, re-derive the 'Testes executados' rows from a run that actually happened, and audit the remaining sixteen Story reports for the same class of claim."
    },
    {
      "id": "F03",
      "severity": "High",
      "story": "MILESTONE",
      "file": "docs/decisions/ADR-0003-agent-review-orchestrator.md",
      "location": "front matter status: \"accepted\"; against CLAUDE.md lines 9-22 at HEAD, tools/opanel-loop/agents/milestone-reviewer.md, tools/opanel-loop/scripts/review-state.sh:88 and :109, commit 4d2fb44",
      "problem": "Commit 4d2fb44 replaced the review orchestration decided by ADR-0003 (still status 'accepted') with tools/opanel-loop, in which a Claude subagent is the independent Milestone reviewer and a script writes reviewing / fix_required / human_acceptance. CLAUDE.md at this HEAD forbids each of those acts by name. No superseding ADR was written, AGENTS.md:9 still declares Codex the independent reviewer, and SPEC_CONFLICTS.md records nothing.",
      "impact": "AGENT_RULES requires a systemic decision or 'a permanent exception to an existing invariant' to become an ADR before it becomes an implicit pattern, and requires a conflict between documentation and implementation to be recorded rather than resolved silently. The repository at HEAD contains a self-contradicting governance set, and the contradiction is precisely about who may declare this Milestone accepted. The work also sits in no Story's declared boundary and is invisible to bin/merge-gate's pipeline-change-authorised check, whose PIPELINE_PATHS contains no tools/ or .claude/ prefix.",
      "evidence": "git show HEAD:CLAUDE.md lines 13-22: 'Claude is never the independent Milestone reviewer. It must not: ... set review-state.json to reviewing, fix_required, accepted or human_acceptance; replace the Codex review with a subagent, fresh Claude context or self-review; modify the orchestrator, its runners, schemas, hook or review/fix role prompts while executing a Milestone or fixing review findings.' git log -- CLAUDE.md shows it unchanged since 298286d. tools/opanel-loop/agents/milestone-reviewer.md: 'You are the independent reviewer of an entire Milestone.' tools/opanel-loop/scripts/review-state.sh:88 writes '.status = \"reviewing\" | .lastReviewer = \"claude\"' and :109 routes ACCEPTED to human_acceptance. docs/decisions/ contains only ADR-0001, ADR-0002 and ADR-0003. review-state.json at f4d869a shows status 'blocked' immediately before the commit.",
      "recommendation": "Write the ADR that supersedes ADR-0003, mark ADR-0003 superseded, update CLAUDE.md and AGENTS.md so the normative instructions match the machinery in use, and record the conflict in docs/implementation/SPEC_CONFLICTS.md."
    },
    {
      "id": "F04",
      "severity": "Medium",
      "story": "MILESTONE",
      "file": "docs/implementation/M00/MILESTONE_REPORT.md",
      "location": "Findings table (lines 109-114) and the six-row 'open Medium' table (lines 123-131)",
      "problem": "The report records 'Medium | 6 | 11' open and enumerates six open Medium findings, but seven exist across the eighteen self-reviews. M00-09 F-3 is omitted. The Low count (12 open) also cannot be reconciled with the reviews, which sum to roughly 22 by their own 'Abertos' figures.",
      "impact": "The Findings table and the 'Human acceptance requested' section are what a human reads to accept the Milestone. One accepted risk — six ESLint rules disabled over the imported component tree, three of them accessibility rules — is not presented for acceptance at all.",
      "evidence": "docs/implementation/M00/review/M00-09.md F-3 'Six ESLint rules are off for the imported component tree', '- **Severidade:** Medium', '- **Estado:** open, resolved by fixing the library upstream', and its own Contagem table: '| Medium | 1 (F-3, owned upstream) |'. It appears in none of the six rows of MILESTONE_REPORT.md's table (M00-17 F-2, M00-12 F-1, M00-08 F-2, M00-05 F-2, M00-05 F-3, M00-03 F-1). Separately, review/M00-12.md:74 claims 'Low 3' while its body contains two Low findings (F-2, F-4).",
      "recommendation": "List all seven open Medium findings, recompute the Low count from the reviews, and add M00-09 F-3 to the 'Human acceptance requested' section."
    },
    {
      "id": "F05",
      "severity": "Medium",
      "story": "M00-14",
      "file": "docs/implementation/M00/MILESTONE_REPORT.md",
      "location": "lines 6-8 and the Quality table line 68; checked by lib/gates/stop_gate.rb:228-249",
      "problem": "The Milestone Report describes a different commit on a different branch — 'Branch: docs/agent-bootstrap', 'Head: f32a344', 'bin/test ... 554 examples' — while HEAD is b9aa412 on loop/replace-orchestrator with a 723-example suite and two rounds of fixes since. StopGate#milestone_report verifies only that eight named headings exist with more than three characters under them, so a report about an entirely different state passes.",
      "impact": "The Stop Gate check whose stated purpose is to stop a Milestone being handed over without an account of itself accepts an account of something else. A reader taking the Quality table at face value gets figures that are 170 examples and roughly twenty commits out of date.",
      "evidence": "MILESTONE_REPORT.md lines 6-8: '- Branch: `docs/agent-bootstrap`', '- Head: `f32a344`'. Line 68: '| `bin/test` (whole suite, lab image present) | **554 examples, 0 failures, 0 pending** | 0 |'. lib/gates/stop_gate.rb:241-244: 'missing = MILESTONE_SECTIONS.reject do |heading| body = contents[...]; body.to_s.strip.length > 3 end' — no commit or branch is compared.",
      "recommendation": "Regenerate the Milestone Report against the commit being handed over, and extend StopGate#milestone_report to require that the report names the current HEAD and branch."
    },
    {
      "id": "F06",
      "severity": "Medium",
      "story": "MILESTONE",
      "file": "docs/implementation/M00/review/M00-17.md",
      "location": "line 3 ('Reviewed diff: 0214fb4..f230511') and line 11; same staleness across all eighteen files in docs/implementation/M00/review/",
      "problem": "Every implementation self-review was last written at 2a38d11 (2026-09-06) or earlier, before roughly twenty fix commits rewrote the code they certify. The reviews' 'Critical 0 / High 0' therefore describes superseded code.",
      "impact": "The Exit Gate condition 'Critical = 0 e High = 0 no review de todas as Stories', and the reviewer-findings checks in lib/gates/post_commit.rb and lib/gates/stop_gate.rb, are satisfied by reviews of code that no longer exists in that form. AGENT_RULES requires the diff to be self-reviewed before it is committed.",
      "evidence": "git log -1 -- docs/implementation/M00/review/M00-17.md returns 2a38d11 (2026-09-06). review/M00-17.md:3 records 'Reviewed diff: `0214fb4..f230511`' and :11 'no finding — 15 examples against a real Engine'. Commit fa0429d (2026-09-07) subsequently rewrote lib/gates/swarm_lab.rb's endpoint resolution, allowlist matching and inventory semantics, and spec/integration/swarm_lab_spec.rb now contains 36 top-level examples. The same pattern holds for M00-08 (3d371a2), M00-10 and M00-11 (ebbf455), M00-12 (e3817c8), M00-13 (0a7b19a) and M00-14 (7844bab), whose reports were updated by the fixes while their reviews were not.",
      "recommendation": "Update the eighteen review files to cover the fix commits, or add a per-fix-round review, so the recorded Critical = 0 / High = 0 describes the code at HEAD."
    },
    {
      "id": "F07",
      "severity": "Medium",
      "story": "M00-12",
      "file": "lib/gates/acceptance_mapping.rb",
      "location": "lines 67-89 (Verifier#verifiable?, #path?, #named_in_code?)",
      "problem": "A criterion is satisfied when any one backticked token in its evidence cell resolves, and named_in_code? accepts any string of six or more characters containing three letters that occurs anywhere in a corpus spanning spec/**, app/**, lib/**, bin/*, config/**, db/**, .github/** and package.json. The check moved from 'the author ticked a box' to 'the author quoted something that exists somewhere', which is not 'the evidence proves the criterion'.",
      "impact": "A criterion whose principal artifact does not exist still passes if any other quoted token in the same cell happens to resolve. This is the failure mode — a check accepting the shape of evidence rather than its content — that the M00-R07 fix was meant to close.",
      "evidence": "lib/gates/acceptance_mapping.rb:68: 'text.scan(QUOTED).flatten.any? { |token| path?(token) || named_in_code?(token) }'; :86: 'return false if needle.length < 6 || !needle.match?(/[A-Za-z]{3}/)'. Demonstrated at docs/implementation/M00/reports/M00-14.md:65 and :72, which cite `config/schemas/tasks.schema.json` as the artifact satisfying AC1 and AC8. git log --all -- config/schemas/tasks.schema.json is empty; the schema is at config/pack/tasks.schema.json. Both criteria pass because `bin/pack validate` and `docs/implementation/README.md` resolve in the same cells.",
      "recommendation": "Require every quoted reference in an evidence cell to resolve rather than one, and prefer a path or a test description over a bare token; raise the minimum needle length and exclude tokens that match common prose."
    },
    {
      "id": "F08",
      "severity": "Medium",
      "story": "M00-11",
      "file": "bin/merge-gate",
      "location": "lines 137-160 (Runner#ci_green), against bin/_gate_lib.sh:138-177 (gate_write_json)",
      "problem": "gate_write_json records commit, branch and dirty in every gate result specifically so an archived result names the code it describes, but ci_green reads only the result field. A CI result produced at any commit, on any branch, or over a dirty tree satisfies the Merge Gate.",
      "impact": "The M00-R19 fix is present in the producer and ignored by the consumer, so the gate that decides whether a merge may proceed cannot distinguish a green run of this commit from a green run of a different one. Combined with F01, nothing in the repository ties any CI result to the code being merged.",
      "evidence": "bin/merge-gate:149: 'result = JSON.parse(File.read(path))[\"result\"]; failed << \"#{job} (#{result})\" unless result == \"pass\"' — no other field is read. bin/_gate_lib.sh:147-150 computes commit, branch and dirty and writes them. tmp/ci-results/static.json currently records '\"commit\": \"ca7f2a37d254391472d6fb20e6225d828f2ea696\", \"dirty\": true' while HEAD is b9aa412, and ci_green would pass on it.",
      "recommendation": "Make ci_green reject a result whose commit is not HEAD, whose branch differs, or whose dirty flag is true, with the reason named."
    },
    {
      "id": "F09",
      "severity": "Medium",
      "story": "M00-17",
      "file": "config/architecture/fitness.yml",
      "location": "the docker_boundaries block and its preceding comment",
      "problem": "AF-02's Tier-0 allowlist was widened from app/executors/ to include spec/support/swarm_lab, bin/swarm-lab and lib/gates/swarm_lab.rb, while the file's own comment states that adding a path there 'is a Tier-0 security change (Annex C §8). It needs an ADR, not a Story.' No such ADR exists.",
      "impact": "The control that keeps the Docker socket inside a single boundary was relaxed through the process it explicitly says is insufficient. The substance is defensible for M00 — the three entries are test and gate tooling with no route and no application caller — but the artifact the control demands for its own modification is absent, and the human is asked to accept a Tier-0 change through a Story report.",
      "evidence": "config/architecture/fitness.yml: '# **Adding a path here is a Tier-0 security change** (Annex C §8). It needs an ADR,\\n# not a Story.' followed by 'docker_boundaries:\\n  - app/executors/\\n  - spec/support/swarm_lab\\n  - bin/swarm-lab\\n  - lib/gates/swarm_lab.rb'. ls docs/decisions/ shows only ADR-0001, ADR-0002, ADR-0003, README.md and pending-documentation-updates.md; grep for docker_boundaries or AF-02 across docs/decisions/ returns nothing. Disclosed as Medium in docs/implementation/M00/review/M00-17.md F-2.",
      "recommendation": "Write the Tier-0 ADR covering the three entries with the reason, the owner and the condition under which they are removed, or narrow docker_boundaries and exempt the harness through fitness_self_referential instead."
    },
    {
      "id": "F10",
      "severity": "Low",
      "story": "M00-10",
      "file": "bin/security",
      "location": "lines 101-102 (comment), against config/ci/jobs.yml:64; the same claim in bin/gate:202-203",
      "problem": "Two gate scripts state that CI scans the whole tree and the branch history, but no CI job passes --history. The only invocation in the repository is spec/security/security_scan_spec.rb:120.",
      "impact": "Milestone AC14 ('secret scan em toda a história do branch') is still covered, because that spec runs inside the security-fast job's 'controls' command, but the stated mechanism is wrong. A maintainer who trusts the comment and later moves the security suite out of that job would silently lose history scanning.",
      "evidence": "bin/security:101-102: '**CI always scans the whole tree and the history**: the scope moves, the check does not.' bin/gate:202-203: 'Scoped to the diff for speed; the `security-fast` CI job scans the whole tree and the history.' config/ci/jobs.yml:64: '- [\"scan\", \"bin/security --out tmp/security/security-report.json\"]' — no --history. grep -rn -- '--history' across bin/, config/, .github/, lib/ and spec/ returns only bin/security's own option parsing and spec/security/security_scan_spec.rb:120.",
      "recommendation": "Add --history to the security-fast job's scan command, or correct both comments to say that history coverage comes from the security suite."
    },
    {
      "id": "F11",
      "severity": "Low",
      "story": "MILESTONE",
      "file": "docs/implementation/M00/review-state.json",
      "location": "maxReviewAttempts changed 3 to 4 in commit 4d2fb44; maxFixAttempts changed 3 to 4 in commit ca7f2a3",
      "problem": "The retry budgets that stop a review/fix loop were raised by direct edit of review-state.json, by the party the budget constrains. tools/opanel-loop/scripts/review-state.sh, documented as the only writer of that file so that 'the invariants are mechanical rather than remembered', exposes no command that changes either field.",
      "impact": "AGENT_RULES and CLAUDE.md require the retry budget to be respected; a budget that can be raised by hand when it is about to be exhausted is not a budget. The stated rationale — that a CLI execution failure is not a verdict and should not spend an attempt — is sound and is recorded in the commit messages, and the same reasoning is now encoded in review-state.sh's cmd_error, so the effect here is procedural rather than substantive.",
      "evidence": "git show f4d869a:docs/implementation/M00/review-state.json shows '\"maxReviewAttempts\": 3, \"maxFixAttempts\": 3'; git show 4d2fb44:...review-state.json shows '\"maxReviewAttempts\": 4'; commit ca7f2a3 'chore(M00): give the fix budget a spare attempt before the new loop's first run' changes one line, raising maxFixAttempts to 4. tools/opanel-loop/scripts/review-state.sh's command list is init|status|set|review-start|verdict|fix-start|fix-done|block|error|attempt-number — none of which writes maxReviewAttempts or maxFixAttempts.",
      "recommendation": "Add an explicit review-state.sh command that adjusts the budgets and records the reason, and forbid hand edits to review-state.json in the guard hooks."
    }
  ]
}
```
agentId: a95884bede6c7a511 (use SendMessage with to: 'a95884bede6c7a511', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 280356
tool_uses: 84
duration_ms: 898916</usage>
