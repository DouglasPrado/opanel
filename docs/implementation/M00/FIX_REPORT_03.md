# Fix Report — M00, attempt 03

Answers [`MILESTONE_REVIEW_03.md`](MILESTONE_REVIEW_03.md) — `NOT_ACCEPTED`,
Critical 0, High 3, Medium 6, Low 2, reviewed at `b9aa412`.

- Milestone: `M00` — Foundation
- Fix attempt: **4** of 5 (`review-state.json.fixAttempt`)
- Branch: `loop/replace-orchestrator`
- Role: IMPLEMENTER. This report carries **no verdict**. Only the independent
  reviewer may emit one.

Three blocking findings. One was corrected outside the loop before this attempt
opened and is verified here rather than redone. One was a documentation defect
and is corrected with a real run behind every number. The third asked for
something no amount of reading could produce — an execution — and produced, on
first contact with a runner, six defects that two rounds of review had not seen.
One of them is a secret scan that had been reporting clean because its own
allowlist silenced it.

## What the human authorised for this round

- pushing `loop/replace-orchestrator`;
- using the pull request to run the pipeline;
- F03 already corrected outside the loop at `a72d83c` — verify and record, do not
  redo.

Two things happened during the round that the authorisation did not anticipate,
and both are recorded here rather than worked around silently:

1. **The branch was merged to `main` twice while this round was running.** PR #3
   was merged at 13:33 UTC with the pipeline still red, so
   `loop/replace-orchestrator` no longer had an open pull request and a push to it
   triggered nothing — `.github/workflows/ci.yml` fires on `pull_request`, on
   `push` to `main`, and on `workflow_dispatch`. Without a pull request there is no
   `merge-stage` (`e2e-critical`, `swarm-smoke`) and no `merge-gate` job at all,
   which is most of what F01 asks to see run. **PR #4** was opened from the same
   branch onto the same base, for the same purpose the authorisation named, and the
   human merged that one too once the ten jobs came back green. Both merges are
   the human's, both are recorded in the run table below, and neither was
   requested by this session.
2. **Editing anything under `.github/` required an approval this session cannot
   obtain.** The edit was attempted and refused by the harness, not skipped. One
   defect and one gate consequence are therefore left open below rather than
   fixed, each with the exact change it needs. Neither is a judgement that they
   should not be fixed.

## Commits

| Commit | Story | What it answers |
|---|---|---|
| `62a2a10` | M00-11 | F01 — the lockfile that made every job fail identically |
| `d102e20` | M00-06, M00-08, M00-10, M00-12 | F01 — the four defects the running pipeline then found |
| `30f4a27` | M00-06, M00-14, M00-15 | F02 — the false test evidence, and the audit |
| `482c45c` | M00-10 | F01 — the allowlist that was silencing the secret scan |

Every file touched is inside its Story's declared boundary in `boundaries.yml`:

| Path | Story |
|---|---|
| `Gemfile.lock` | M00-11 |
| `bin/setup` | M00-06 |
| `bin/redact-artifacts`, `spec/security/artifact_redaction_spec.rb` | M00-08 |
| `spec/security/workspace_guardrail_spec.rb`, `spec/security/security_scan_spec.rb`, `config/security/**` | M00-10 |
| `spec/gates/**` | M00-12 |
| `docs/implementation/M00/reports/**` | pack bookkeeping, allowed everywhere |

**No boundary was widened in this round**, and nothing under `.github/` was
changed — see the two open items below for what that costs.

---

## F01 — the CI pipeline had never executed

**High. Story M00-11. Answered in substance; one Required Test remains open.**

The review's argument was that a pipeline nobody has run is a pipeline nobody has
tested, and that the `mktemp` defect of round two — which would have aborted
`gate_begin` on every Ubuntu runner before a single check ran — was the proof
that local and CI are materially different environments.

That argument was right, and the first execution settled it: **12 jobs, 12
failures**, run `34230657160` at `67776a7`. Then five more defects, each of which
survives any amount of reading and dies on contact with a Linux runner.

### The six defects, at their cause

**1. The lockfile recorded one platform: the implementer's laptop.**

```
Your bundle only supports platforms ["arm64-darwin"] but your local platform is
x86_64-linux. Add the current platform to the lockfile with
`bundle lock --add-platform x86_64-linux` and try again.
##[error]The process '…/bundle' failed with exit code 16
```

Identically, in all twelve jobs, in the composite `setup` action, before any job
ran a single command of its own. `bundle lock --add-platform x86_64-linux` adds
the platform and the two native gems that need a build for it (`nokogiri`, `pg`)
with their checksums. No dependency changed version. `62a2a10`.

**2. `bin/setup` asked the wrong PostgreSQL.** (`setup` job)

```
bin/setup failed
  PostgreSQL is installed but not accepting connections.
```

`pg_isready` with no arguments asks the local Unix socket. That is correct on a
laptop and wrong wherever the database is a TCP service — and it failed against a
PostgreSQL that `bin/rails db:test:prepare` had connected to two seconds earlier
in the same job. It now reads `OPANEL_DATABASE_HOST` and `OPANEL_DATABASE_PORT`,
the same declarations `config/database.yml` reads, with the same defaults, and
names the endpoint it could not reach.

**3. `require "english"`.** (`security-fast` job)

```
An error occurred while loading ./spec/security/workspace_guardrail_spec.rb.
Failure/Error: require "english"
LoadError: cannot load such file -- english
0 examples, 0 failures, 1 error occurred outside of examples
```

APFS is case-insensitive and resolves it to `English.rb`; ext4 does not. The
whole `controls` command of the `security-fast` job died on it. It is
`require "English"`. A survey of every `require` of a stdlib-looking name in the
repository found this to be the only occurrence — `bin/setup:18` already had it
right.

**4. The artifact redactor deleted its own capture manifest.** (`e2e-critical`)

```
redact-artifacts: DELETED tmp/test-results/visual-manifest.jsonl (uninspectable-format (.jsonl))
redact-artifacts: FAIL — 1 artifact(s) could not be cleared and were removed
```

Two defects, one symptom. `.jsonl` was missing from `TEXT_EXTENSIONS`, so a
manifest *with* entries only survived by accident, through the byte sniff below
it. And the sniff read `!sample.empty?`, so a file with nothing in it went down
the binary path to be deleted as unreadable — "nobody could read it", applied to
a file with no bytes. `e2e/support/global-teardown.ts` writes `''` when no visual
artifact resolved, which is why this **passed on one run and failed on the next**,
five minutes apart on the same code: run `34232512326` produced captures, run
`34232728268` produced none.

Reproduced and fixed locally, independent of CI:

```
$ git show HEAD:bin/redact-artifacts > /tmp/old-redact-artifacts && chmod +x /tmp/old-redact-artifacts
$ : > "$D/visual-manifest.jsonl" && /tmp/old-redact-artifacts "$D"
redact-artifacts: DELETED …/visual-manifest.jsonl (uninspectable-format (.jsonl))
redact-artifacts: FAIL — 1 artifact(s) could not be cleared and were removed
exit=1
$ : > "$D/visual-manifest.jsonl" && ./bin/redact-artifacts "$D"
redact-artifacts: PASS (1 artifact(s), 0 masked, 0 visual entr(ies) covered)
exit=0
```

The three guards above the sniff are untouched, so **an empty `.png` is still an
unproven visual artifact and an empty `.zip` is still an archive nobody could
open** — both are asserted by new examples, alongside a third proving that a
`.jsonl` reaching the text path is *scanned* rather than waved through. Adding an
extension to an allowlist without a scan would be a hole; this is not that.

**5. The git-hook check asserted the state of whichever machine ran it.**
(`unit` job)

```
install-hooks: core.hooksPath is 'unset', expected '.githooks'
```

`spec/gates/gate_scripts_spec.rb`'s AC4 example ran `bin/install-hooks --check`
against the working checkout and required it to pass. On a developer machine it
passed because `bin/setup` had run; on a fresh runner nobody had run it. What it
proved was that somebody, once, ran a script — not a property of the code. It now
proves the round trip in a scratch repository reached through
`GIT_DIR`/`GIT_WORK_TREE`: `--check` refuses a repository that is not configured,
`bin/install-hooks` configures it, `--check` then agrees. Two assertions where
there was one, and it never touches the hooks of the checkout it runs in — an
example that unset them and then died would silently disable the gate it tests.

**6. The secret scan was silenced by its own allowlist.** (`security-fast`)

With the suite loading again, three planted-secret examples reported:

```
the secret scan did not detect a planted key:
1:50PM INF scanned ~0 bytes (0) in 1.76ms
1:50PM INF no leaks found
```

Not a failure to detect. A failure to run. `config/security/gitleaks.toml`
allowlisted `tmp/.*`, unanchored, which matches **any path containing `tmp/`** —
including `/tmp`, where `Dir.mktmpdir` puts a scratch directory on Linux. The
examples use a scratch directory *precisely* to stay out of the repository's
allowlisted `tmp/`, and on Linux they planted their fixture straight into the
allowlist. macOS puts a scratch directory under `/var/folders`, so they passed
here through two review rounds.

An allowlist entry that silences a scanner outside the directory it was written
for is the same defect this Milestone keeps finding: a control reporting clean for
the wrong reason. `^tmp/` is what the entry always meant. The fixture now sits one
level under a `tmp/` inside the scratch root, so its path has the same shape on
every platform and an un-anchored entry fails these examples everywhere rather
than only where they happen to run. Verified both directions against
`gitleaks 8.30.1`, on this machine, before the change was committed:

| Config | Fixture | Result |
|---|---|---|
| `tmp/.*` | `<scratch>/tmp/planted.txt` | `scanned ~0 bytes (0)`, no leaks — the defect |
| `^tmp/` | `<scratch>/tmp/planted.txt` | `scanned ~39 bytes`, `leaks found: 1` |
| `^tmp/` | repository scan, key planted in `tmp/probe-scan/` | no leaks — the repository's own `tmp/` still allowlisted |

`node_modules/` and `vendor/bundle/` stay unanchored deliberately: those nest, and
an entry covering only the top-level copy would be wrong. `tmp/` does not nest.

### What remains open on F01

**The five negative pull requests are not delivered.** `M00-11` Required Tests
asks for "cinco PRs de teste, um por classe de falha (2–6), cada um
comprovadamente bloqueado". The authorisation for this round covered one pull
request, for the green run. Five more, each carrying a deliberately planted
failure, are five outward-facing acts on a repository the implementer does not
own the decision for, and `FIX_REPORT_02.md` declined them for the same reason.
The five classes are proved locally against `bin/ci-job` in
`spec/gates/ci_pipeline_spec.rb`; that is a simulation and this report does not
call it anything else. The review's own Required Fix offers the alternative —
"open a Story/ADR that formally replaces that criterion" — and that is a
governance decision, not an implementer's. **Open, named, not substituted.**

**`unit` never runs the two examples that plant a real secret.** gitleaks is
installed only for `security-fast`, so in the `unit` job both examples report
`# gitleaks is not installed` and skip — explicitly, which is the designed
behaviour, and never silently green. The fix is one line in
`.github/workflows/ci.yml`:

```yaml
      - name: gitleaks
        if: matrix.job == 'security-fast' || matrix.job == 'unit'
```

Editing that file requires an approval this session cannot obtain, so it is
recorded rather than applied.

### The pipeline, run

Six executions, each one a real event with a URL. The progression is the
evidence, not the last line of it:

| Run | Commit | Result |
|---|---|---|
| [`34230657160`](https://github.com/DouglasPrado/opanel/actions/runs/34230657160) | `67776a7` | **12 red.** Every job at `bundle install`, exit 16 |
| [`34232512326`](https://github.com/DouglasPrado/opanel/actions/runs/34232512326) | `62a2a10` | 6 green, 3 red (`setup`, `security-fast`, `unit`), `pr-gate` and `merge-gate` red |
| [`34234341338`](https://github.com/DouglasPrado/opanel/actions/runs/34234341338) | `30f4a27` | 9 of 10 green; `security-fast` red on the silenced scan |
| [`34235400571`](https://github.com/DouglasPrado/opanel/actions/runs/34235400571) | `482c45c` | **all ten `required_for_merge` jobs green, `pr-gate` green** |
| [`34237841689`](https://github.com/DouglasPrado/opanel/actions/runs/34237841689) | `dcd31cf` | push to `main` after the human merged PR #4 — **`conclusion: success`** |
| [`34239482957`](https://github.com/DouglasPrado/opanel/actions/runs/34239482957) | `48c9515` | `workflow_dispatch` on this report's own commit — **`conclusion: success`** |

Run `34235400571`, `pull_request` on PR #4, started 13:59:27Z:

| Job | Result | Duration |
|---|---|---|
| `static` | success | 62s |
| `unit` | success | 152s |
| `integration` | success | 87s |
| `contract` | success | 51s |
| `security-fast` | success | 98s |
| `frontend` | success | 60s |
| `migrations` | success | 60s |
| `setup` | success | 74s |
| `e2e-critical` | success | 93s |
| `swarm-smoke` | success | 76s |
| `pr-gate` | **success** | 5s |
| `merge-gate` | failure | 11s — see below |

`pr-gate` is the check branch protection requires, and it does not accept
"nothing red": it requires each named job to have reported `success`, so a
skipped or cancelled job fails it. It reported `pr-gate: PASS`.

That covers what the first real run could not: the composite `setup` action, the
gitleaks install, the PostgreSQL service wiring, the Playwright browser install,
the `docker pull` of the lab image against a real Engine, `actions/upload-artifact`
and `actions/download-artifact` (ten artifacts, downloaded), and the archive
action's redaction step — which is where two of the six defects were found.

---

## F02 — test evidence for runs that could not have happened

**High. Stories M00-06 and M00-15. Corrected, with a real run behind every
number.**

Two required Stories recorded `rspec` green against spec files that have never
existed on any branch. `git log --oneline --all` for all three paths returns
nothing. A run against a missing path errors; it does not pass. The behaviour was
covered the whole time — what was false was the record, which is precisely the
failure mode this Milestone was built to make impossible.

| Report | Claimed | Exists | Re-run |
|---|---|---|---|
| `reports/M00-06.md` | `spec/integration/setup_spec.rb`, `spec/integration/dev_supervisor_spec.rb` | `spec/integration/development_environment_spec.rb` (`b8a5f82`) | 21 examples, 0 failures, exit `0` |
| `reports/M00-15.md` | `spec/integration/health_spec.rb` | `spec/requests/health_spec.rb` (`524e9ed`) | 10 examples, 0 failures, exit `0` |

Both the "Arquivos alterados" and the "Testes executados" tables are corrected —
`FIX_REPORT_02.md` fixed only the Acceptance Criteria row that
`lib/gates/acceptance_mapping.rb` reads and left the same claim standing in two
other tables of the same file, which is a fix fitted to the check rather than to
the problem.

`M00-15` also recorded that run as **"green, including PostgreSQL stopped"**.
Nothing in this Milestone stops PostgreSQL. `spec/requests/health_spec.rb`
proves the unreachable-database path by returning a classified
`DatabaseConnection::Result` from `.check`; the classification of the real driver
messages is proved separately, against those messages, in
`spec/unit/database_connection_spec.rb`. Acceptance Criterion 7 now says which of
the two proves what, and does not claim a server was stopped.

### The audit of the other sixteen reports

Mechanical, then resolved by hand. 297 backticked paths across the eighteen
reports; 34 do not exist on disk:

| Class | Count | Verdict |
|---|---|---|
| Brace shorthand for files that exist — `spec/integration/{jobs,queue_configuration,worker_crash}_spec.rb` | 18 | accurate |
| Paths the report itself records as deleted or removed — `app/assets/`, `app/views/pwa/`, `config/master.key`, `config/credentials.yml.enc`, `app/views/home/show.html.erb` | 7 | accurate |
| Prose shortening a real path — `lib/utils.ts` for `app/frontend/lib/utils.ts`, `spec/support/swarm_lab` for `…/swarm_lab.rb` | 5 | imprecise, not false; the tables name them correctly |
| Parsing noise (`app/executors/"`) | 1 | not a claim |
| **F02 — never existed** | 3 | corrected above |
| **`config/schemas/tasks.schema.json` in `reports/M00-14.md` — never existed** | 1 | corrected; the schema is `config/pack/tasks.schema.json` |

The last one is the path `MILESTONE_REVIEW_03.md` F07 uses to demonstrate that
`lib/gates/acceptance_mapping.rb` passes a criterion when **any one** quoted token
in the cell resolves. The path is corrected here. The verifier that accepted it is
F07, Medium, and stays open — correcting the path without correcting the verifier
would be the fix fitted to the check again, and this report says so rather than
letting the corrected path imply otherwise.

Four reports also record the F01 repairs against the Stories that own the files:
`M00-06` (`bin/setup`), `M00-08` (`bin/redact-artifacts`), `M00-10` (the
`require`), `M00-12` (the hook example).

---

## F03 — the orchestration decision had no ADR

**High. MILESTONE. Corrected outside the loop at `a72d83c`; verified here, not
redone.**

The human corrected this before this attempt opened, because the finding is about
the loop itself and no Story's boundary contains it. Verified at this HEAD:

| What the review required | State |
|---|---|
| An ADR superseding ADR-0003 | `docs/decisions/ADR-0004-in-process-milestone-loop.md`, `status: "accepted"`, `supersedes: "ADR-0003"` |
| ADR-0003 marked superseded | front matter `status: "superseded"`, `superseded-by: "ADR-0004"`, with the pointer in the body |
| `CLAUDE.md` matching the machinery in use | §"Fixed Role — IMPLEMENTER" now states the rule plainly — "the session implementing a Milestone must not review it" — and cites ADR-0004 |
| `AGENTS.md` no longer declaring Codex the reviewer | §"Fixed Role — REVIEWER" now says the review runs in-process as the `milestone-reviewer` subagent, and keeps this file as the entrypoint for an external reviewer |
| An entry in `SPEC_CONFLICTS.md` | **SC-16**, `resolved`, naming F03 as how it surfaced and ADR-0004 as the resolution |

`ADR-0004` states the trade rather than hiding it: what is given up is the
different vendor, so a blind spot shared by implementer and reviewer is less
likely to be caught; what carries the independence without the vendor — fresh
context, different model, read-only grant, a verdict written by
`review-state.sh` and not by prose — was already what ADR-0003 relied on.

Nothing was re-done here, and the reviewer should judge `a72d83c` on its own
terms rather than on this summary of it.

---

## Findings recorded and left open

Per `docs/goals/FIX_REVIEW_FINDINGS.md`, only `Critical` and `High` are corrected
in a fix round. The eight non-blocking findings of `MILESTONE_REVIEW_03.md` are
recorded here unfixed, with one exception noted:

| ID | Severity | Subject | State |
|---|---|---|---|
| F04 | Medium | `MILESTONE_REPORT.md` omits the seventh open Medium (M00-09 F-3) and understates the Low count | open |
| F05 | Medium | `MILESTONE_REPORT.md` describes `f32a344` on `docs/agent-bootstrap`; `StopGate#milestone_report` cannot tell | open |
| F06 | Medium | the eighteen self-reviews predate the code they certify | open |
| F07 | Medium | `acceptance_mapping.rb` accepts a criterion when any one quoted token resolves | open — the one false path it accepted is corrected, the verifier is not |
| F08 | Medium | `bin/merge-gate`'s `ci_green` reads `result` and ignores `commit`, `branch`, `dirty` | open |
| F09 | Medium | AF-02's Tier-0 list widened without the ADR `fitness.yml` demands for itself | open |
| F10 | Low | `bin/security` and `bin/gate` assert a `--history` scan no CI job performs | open |
| F11 | Low | the retry budgets were raised by hand in `review-state.json` | open |

F04 and F05 both ask for the Milestone Report to be regenerated against the
commit being handed over. That is a real gap and it is deliberately not closed in
this round: the report a human reads to accept the Milestone should describe the
state the reviewer accepted, and this attempt does not know what that state is
yet. Regenerating it now would produce a third account of a fourth commit.

---

## The merge gate, and what it says

`merge-gate` runs only on a pull request. At run `34235400571`, with all ten
required jobs green, it reports six of nine conditions met and **fails**. That is
the correct outcome and this report does not present it as anything else — but
the three red items are of two different kinds, and only one of them is the gate
working.

| Check | State | Why |
|---|---|---|
| `base-branch-current` | **green** | the job checks out `refs/remotes/pull/<n>/merge`, so the base is an ancestor by construction |
| `migration-rollout-safe`, `rollback-known`, `story-status-consistent`, `documentation-current`, `pipeline-change-authorised` | **green** | |
| `required-approvals` | **red, and correctly so** | "the pull request is not reviewed". GitHub does not let an author approve their own pull request, and this gate exists so a human signs off. It is the machine working, and the implementer cannot and should not clear it. |
| `ci-green` | **red on a defect** | `no result for static, unit, … — a required job that did not run is not a job that passed` |
| `critical-zero`, `high-zero` | **red on the same defect** | `no security report at tmp/security/security-report.json` |

The `ci-green` diagnosis, because it is a real finding and not an accident of
this round: `.github/actions/archive/action.yml` uploads three paths —
`tmp/ci-results/`, `tmp/test-results/`, `tmp/security/` — and
`actions/upload-artifact@v4` roots an artifact at the **least common ancestor** of
its paths, which is `tmp/`. The artifact therefore contains `ci-results/…`, not
`tmp/ci-results/…`. `ci.yml` then downloads with `path: .`, so the evidence lands
at `./ci-results/` while `bin/merge-gate` reads `tmp/ci-results/<job>.json` and
finds nothing. Ten artifacts download successfully and every required job is
reported missing.

The fix is one line, on the consumer side of `ci.yml`:

```yaml
      - uses: actions/download-artifact@v4
        with:
          pattern: evidence-*-${{ github.run_id }}-*
          merge-multiple: true
          path: tmp
```

It is **not** applied, for the reason given at the top: editing `.github/**`
requires an approval this session cannot obtain. It is also deliberately not
worked around in `bin/merge-gate`: teaching the gate to look wherever the
producer happened to drop the files would make `ci_green` accept evidence from an
unspecified location, which is the direction F08 already says it is too loose in.
A gate is not edited to make a run pass.

---

## Commands run

Local, on this machine, with Homebrew Ruby 4.0.6 on `PATH`:

| Command | Result | Exit |
|---|---|---|
| `bundle lock --add-platform x86_64-linux` | lockfile rewritten; `PLATFORMS` gains `x86_64-linux` | `0` |
| `bundle exec rspec spec/integration/development_environment_spec.rb` | 21 examples, 0 failures | `0` |
| `bundle exec rspec spec/unit/log_formatter_spec.rb` | 16 examples, 0 failures | `0` |
| `bundle exec rspec spec/requests/health_spec.rb` | 10 examples, 0 failures | `0` |
| `bundle exec rspec spec/unit/database_connection_spec.rb` | 15 examples, 0 failures | `0` |
| `bundle exec rspec spec/security/` | 131 examples, 0 failures | `0` |
| `bundle exec rspec spec/gates/gate_scripts_spec.rb spec/security/workspace_guardrail_spec.rb spec/integration/development_environment_spec.rb` | 109 examples, 0 failures | `0` |
| `bundle exec rspec spec/security/artifact_redaction_spec.rb` | 28 examples, 0 failures | `0` |
| `bundle exec rspec spec/security/security_scan_spec.rb` | 56 examples, 0 failures | `0` |
| `bin/gate pre-commit` (hook, at `62a2a10`) | 8 checks PASS | `0` |
| `bin/gate pre-commit` (hook, at `d102e20`) | 8 checks PASS | `0` |
| `bin/gate pre-commit` (hook, at `30f4a27`) | 8 checks PASS | `0` |
| `bin/gate pre-commit` (hook, at `482c45c`) | 8 checks PASS | `0` |

The four `bin/gate pre-commit` runs are the git hook, not a separate invocation:
`core.hooksPath` is `.githooks` and every commit in this round went through it.
No commit in this round used `--no-verify`.

Closing verification, at `482c45c`:

```
$ bin/gate local
  format                 PASS  1668ms
  lint                   PASS  3032ms
  typecheck              PASS  1817ms
  tests                  PASS  389269ms
  frontend-tests         PASS  2600ms
  migrations             PASS  53ms
  contracts              PASS  350ms
  security               PASS  38029ms
  fitness                PASS  190ms
gate:local: PASS (437470ms)                                      exit 0
```

```
$ bin/stop-gate M00
ok=true
  workspace-clean      pass
  pack-consistent      pass
  static               pass
  security             pass
  unit                 pass
  integration          pass
  contract             pass
  acceptance           pass
  findings             pass
  milestone-report     pass                                     exit 0
```

`milestone-report` passing is not evidence that `MILESTONE_REPORT.md` is current.
It checks that eight named headings exist with something under them, which is
exactly the weakness `MILESTONE_REVIEW_03.md` F05 describes, and F05 is open. This
report says so rather than letting a green check imply otherwise.

And in CI, which is the point of this round:

```
run 34235400571 — pull_request, PR #4, commit 482c45c
  static unit integration contract security-fast frontend migrations setup
  e2e-critical swarm-smoke                                     10/10 success
  pr-gate                                                          PASS
  merge-gate                                                       FAIL — three
    conditions, one of them a human approval this session must not clear and
    two of them the artifact-path defect diagnosed above.
```

Two more runs happened after that one, and both belong in the record because the
branch moved under this report while it was being written.

**The human merged PR #4 at `482c45c`**, once the ten jobs came back green — the
second merge of this round, and the reason the account here has to be checked
against `gh` rather than read. That merge pushed to `main`, which is a trigger:

```
run 34237841689 — push to main, commit dcd31cf (the merge of 482c45c)
  conclusion: success
  ten required_for_merge jobs   success
  pr-gate                       success
  merge-gate                    skipped — it runs only on a pull request, by
    design: after a push to main the merge has already happened and there is
    nothing left to gate.
```

That is the whole workflow reporting `success` for the first time in this
repository's history, on a commit containing every fix of this round.

**This report's own commit, `48c9515`, is documentation only** and had no open
pull request to run against, so the pipeline was dispatched on it directly:

```
run 34239482957 — workflow_dispatch, branch loop/replace-orchestrator, commit 48c9515
  conclusion: success
  static unit integration contract security-fast frontend migrations setup  8/8 success
  pr-gate                       success
  merge-stage, merge-gate       skipped
```

`e2e-critical` and `swarm-smoke` do not run on a `workflow_dispatch` of a
non-default branch — `merge-stage` is gated on
`github.base_ref == 'main' || github.ref == 'refs/heads/main'`. So this run proves
the PR stage at the exact tree being handed to review, and the merge stage is
proved at `482c45c` and `dcd31cf`, which differ from it by one Markdown file.
Both statements are checkable:

```sh
gh run view 34239482957 --json conclusion,headSha
gh run view 34237841689 --json conclusion,headSha
git diff --stat 482c45c..48c9515
```

One honest limit, because it is the kind of gap that otherwise looks like a
missing number: the paragraphs you are reading are in a commit that *postdates*
run `34239482957` — the branch's last commit amends this report with the two runs
above. A report cannot carry the id of the run of the commit that carries the
report. That commit changes one Markdown file, the pipeline is dispatched on it
too, and the reviewer reads the result where it lives:

```sh
gh run list --branch loop/replace-orchestrator --limit 2
git diff --stat 48c9515..HEAD
```

---

## What the next review should be able to verify

Stated as checks, not as claims, because that is the whole argument of the round:

1. `gh run view 34235400571` — ten `required_for_merge` jobs `success` and
   `pr-gate` `success`, at `482c45c`, on a `pull_request` event; and
   `gh run view 34237841689 --json conclusion` — the whole workflow `success` at
   `dcd31cf` on `main`.
2. `gh run view 34230657160` — twelve failures at `67776a7`, so the progression is
   an event rather than a story about one.
3. `git log --all -- spec/integration/setup_spec.rb spec/integration/dev_supervisor_spec.rb spec/integration/health_spec.rb`
   is empty. `grep -rn 'setup_spec\|dev_supervisor_spec\|integration/health_spec' docs/implementation/M00/reports/`
   returns three lines, all inside the "Corrected at fix attempt 03" notes that
   quote what the claim used to be. No table names them. Deleting the names would
   have hidden the correction rather than recorded it.
4. `docs/decisions/ADR-0004-in-process-milestone-loop.md` is `accepted`,
   `ADR-0003` is `superseded`, `SPEC_CONFLICTS.md` SC-16 is `resolved`.
5. Each of the six repairs carries a test that fails without it. The two worth
   checking hardest are the redactor — `git stash` the change and run
   `spec/security/artifact_redaction_spec.rb` — and the allowlist, where the
   three-row table above is reproducible with `gitleaks` in one command.
6. The four items this round leaves open are named in their own sections and
   none of them is described as done: the five negative pull requests, the
   gitleaks step for `unit`, the artifact path `merge-gate` reads, and the eight
   non-blocking findings.
