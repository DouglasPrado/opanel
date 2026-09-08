# Fix Report — M00, attempts 02 and 03

Answers [`CODEX_REVIEW_02.md`](CODEX_REVIEW_02.md) — `NOT_ACCEPTED`, Critical 1,
High 9, Medium 0, Low 0, reviewed at `4b357cf`.

- Milestone: `M00` — Foundation
- Fix attempts: **2** and **3** (`review-state.json.fixAttempt`), both against
  the same review — see "Attempt 03" at the end for why there are two.
- Role: IMPLEMENTER. This report carries **no verdict**. Only the independent
  reviewer may emit one.

Read it in two passes. Everything up to "Closing verification" is attempt 02, on
branch `docs/agent-bootstrap`, ending at `6e6322b`. "Attempt 03" re-establishes
the same evidence on branch `loop/replace-orchestrator`, at `ca7f2a3`, which is
the state actually being handed to review.

Ten findings, all blocking, all addressed. Every fix carries the negative test
that proves the defect is gone rather than the assertion that it is — which is
the class of problem most of these findings are about.

The work is seven commits, one per Story, in the shape the previous fix used:
`bin/gate post-commit` compares a commit against **one** Story's declared
boundary, so a single commit spanning nine Stories cannot pass for any of them.

| Commit | Story | Findings |
|---|---|---|
| `fa0429d` | M00-17 | M00-R11, M00-R16 |
| `3d371a2` | M00-08 | M00-R02 |
| `0a7b19a` | M00-13 | M00-R10 |
| `ebbf455` | M00-10 | M00-R09 |
| `874afde` | M00-11 | M00-R17, M00-R18 |
| `7844bab` | M00-14 | M00-R07 (Stop Gate half) |
| `e3817c8` | M00-12 | M00-R06, M00-R07 (acceptance half) |

Each commit was checked against its Story's boundary before it was made, and all
seven pass retroactively.

---

## Critical

### M00-R11 — the destination of the Swarm Lab was not the one the CLI would use

`lib/gates/swarm_lab.rb`, `config/architecture/docker-lab.yml`, `bin/swarm-lab`.
Story M00-17. Commit `fa0429d`.

**The defect.** Three of them, compounding.

1. The guardrail read `DOCKER_HOST`. The Docker CLI does not stop there: with the
   variable unset it uses the **current context**. `docker context use production`
   leaves `DOCKER_HOST` empty, so the destination was classified as the local
   socket — and that is the machine `swarm init` would then have run against.
2. The allowlist was matched with `start_with?`. `tcp://localhost.attacker.example`
   and `tcp://127.0.0.1.example.com` both begin with an allowed entry and neither
   is this machine.
3. The check ran *after* `docker info` and the Engine version check, so a foreign
   endpoint was contacted twice before the guardrail spoke. When that host was
   unreachable, what it said was that the Engine version was too old — observed
   before the fix:

   ```
   $ DOCKER_HOST=tcp://10.0.4.19:2376 bin/swarm-lab up
   Docker  is older than the minimum this platform is developed against (24.0).
   ```

**The fix.** `resolved_endpoint` applies the CLI's own precedence — `DOCKER_HOST`,
then `DOCKER_CONTEXT`, then the current context — and fails closed with
`EndpointUnknown` when the context cannot be read at all. The endpoint is parsed
into scheme and host and matched against a versioned allowlist by **scheme and
exact host**; a `tcp` host must additionally resolve exclusively to a loopback
address, so an allowed *name* pointed elsewhere by `/etc/hosts` or a search domain
is refused. `assert_claimable_endpoint!` runs before this process opens any
connection.

`config/architecture/docker-lab.yml` now declares structured entries rather than
string prefixes, which is what makes exact matching expressible:

```yaml
claimable_endpoints:
  - scheme: "unix"
  - scheme: "npipe"
  - scheme: "tcp"
    host: "127.0.0.1"
```

**Evidence.**

```
$ DOCKER_HOST=tcp://10.0.4.19:2376 bin/swarm-lab up
Refusing to create a Swarm on `tcp://10.0.4.19:2376 (from DOCKER_HOST)`.
…
$ DOCKER_HOST=tcp://localhost.attacker.example:2376 bin/swarm-lab up
Refusing to create a Swarm on `tcp://localhost.attacker.example:2376 (from DOCKER_HOST)`.
```

Both refuse immediately, with no network round-trip.

**Negatives** (`spec/integration/swarm_lab_spec.rb`):

- `"reads the current docker context when DOCKER_HOST is unset"`
- `"refuses a context pointing at a remote daemon"`
- `"still accepts the local socket the default context names"`
- `"prefers DOCKER_HOST over the context, as the CLI does"`
- `"fails closed when the context cannot be read at all"`
- `"refuses tcp://localhost.attacker.example:2376"`, `"…tcp://127.0.0.1.example.com:2376"`,
  `"…tcp://localhost-2.internal:2376"`
- `"refuses an allowed name that does not resolve to loopback"`
- `"refuses an endpoint with no scheme rather than guessing one"`
- `"accepts the loopback host itself"` — so the rule is not passing by refusing
  everything

---

## High

### M00-R16 — a listing that failed read as an empty lab

`lib/gates/swarm_lab.rb`, `bin/swarm-lab`. Story M00-17. Commit `fa0429d`.

**The defect.** `lab_services` and `orphaned_resources` rescued `DockerUnavailable`
into `[]` and `{}`. An enumeration that failed says nothing about what is running;
an empty list says there is nothing. `down` acted on the second reading and
continued to `swarm leave --force`, after which any resource it had not seen
cannot be found at all.

**The fix.** `orphaned_resources` raises `InventoryUnknown` when any of the four
listings fails — every listing or none. `bin/swarm-lab down` refuses before the
irreversible call, `reset` refuses, and `status` reports `unknown` with the reason
instead of `none`.

**Negatives:** one per resource kind (`"refuses to claim the lab is empty when
\`docker service ls\` fails"`, and the same for network, secret and config),
`"reports the inventory as unknown rather than as none"`, and
`"stops \`down\` before \`swarm leave\` instead of tearing down blind"` — which
asserts the refusal appears *before* the irreversible call, not merely that it
exists.

---

### M00-R02 — visual artifacts published without proof of sanitisation

`bin/redact-artifacts`, `e2e/support/masked-capture.ts`,
`e2e/support/global-teardown.ts`. Story M00-08. Commit `3d371a2`.

**The defect.** A screenshot's content is in its pixels. The redactor ran its
patterns over the container's bytes, found nothing — because there is nothing
there for a regex to find — and recorded that as "publishable". A revealed
secret, a token in a field or a session id in a debug panel travelled to CI
storage with it. The screencast frames inside a Playwright trace were never
examined at all.

**The fix**, in two halves, because neither alone is enough.

*At capture.* `e2e/support/masked-capture.ts` extends Playwright's `test` with an
auto fixture that installs a redaction stylesheet through `addInitScript` before
the first navigation — so anything marked `data-sensitive`, `[data-testid$="-secret"]`,
`[data-testid$="-token"]` or `input[type=password]` is hidden in the page and never
reaches a frame. `visibility: hidden`, not a blur: a blur is reversible in
principle and this is the last control before the bytes leave the machine. Both
journeys import from it.

*At publication.* The fixture claims the artifacts the masked test produced;
`global-teardown.ts` turns those claims into sha256 digests once Playwright has
finished writing them, and only then runs the redactor. The split is not
cosmetic — Playwright writes the video and the trace *after* the fixture that
produced them has torn down, so hashing inside the fixture vouched for the
screenshot and silently omitted the two artifacts that record the most. That was
observed during this fix: the first implementation left `video.webm` unclaimed
and the redactor deleted it.

A standalone visual artifact is published only when its digest is in the
manifest. Inside an archive, where no per-file claim exists, the visual entries
are replaced with a placeholder and the archive is rewritten — a trace with blank
frames is still its actions, its network log and its console output.

**Evidence.** A deliberate E2E failure, run and then removed:

```
redact-artifacts: covered 4 visual entr(ies) in …/trace.zip
redact-artifacts: PASS (4 artifact(s), 0 masked, 4 visual entr(ies) covered)

manifest:  test-failed-1.png  918c1aa3c8820a81…
           video.webm         9361a7175dfbab8f…
```

The rewritten trace is still a valid archive, verified with Python's `zipfile`:
`testzip()` returned `None`, `test.trace`, `1-trace.network`, the sources and the
CSS/HTML resources are intact at full size, and the three `screencast/*.jpeg`
frames plus the screenshot attachment are 70 bytes each — the placeholder.

**Negatives** (`spec/security/artifact_redaction_spec.rb`):

- `"deletes a screenshot with no proof of where it came from"`
- `"publishes one the masked capture recorded, bound to its bytes"`
- `"refuses one whose bytes changed after it was recorded"`
- `"still refuses a recorded screenshot carrying a credential in its metadata"`
- `"publishes a font, which records no screen"`
- `"replaces them and leaves the rest of the trace readable"`
- `"still reads the entries it covers, so a credential in one is caught"`
- `"is what the journeys import, so no spec captures unmasked"`

---

### M00-R06 — test coverage overstated, and the frontend not run at all

`bin/test`, `bin/test-metadata`, `bin/gate`, `lib/gates/post_commit.rb`.
Stories M00-07/12/14. Commit `e3817c8`.

**The defect.** `type` stayed `all` however the run had been narrowed — by
`--changed`, by `--fast`, by explicit paths — and `covered_suites` expanded `all`
into every suite name. A Story declaring six suites was cleared by a run of three
spec files. Skips were not rejected either: a skipped example reports `pass` for
the same reason a green one does. And the Ruby spec selector cannot see a change
under `app/frontend/`, so a commit touching only the React tree passed a local
gate that had tested none of it.

**The fix.** `bin/test-metadata` records `scope`, `fast`, `selected_paths` and a
single `complete` field. `covered_suites` credits every suite only for a complete
run, credits a whole-type run for its own type, and credits **nothing** for
evidence written before those fields existed — an unanswerable question is not a
yes. A recorded run with any skipped example is refused, naming the count.

`bin/gate local` reports `frontend-tests` as its own check, skipping explicitly
with a reason when no frontend file changed. The pre-commit `tests` item runs both
languages through `check_related_tests`, staying one of the eight items of Annex I
§12.1 rather than becoming a ninth.

**Consequence worth stating.** `bin/gate local` runs `bin/test --changed`, which
now honestly records a narrowed run — so `bin/gate post-commit` must be preceded
by a full `bin/test`. Before the fix that ordering was invisible because the
narrowed run claimed to be complete.

**Negatives** (`spec/gates/gate_scripts_spec.rb`): `"refuses evidence from a run
narrowed by --changed"`, `"…--fast"`, `"…a path"`, `"refuses evidence written
before the selection was recorded"`, `"refuses a run that skipped examples"`, and
`"credits a whole-type run for the type it ran"`.

---

### M00-R07 — criteria and reports satisfied by declaration

`lib/gates/acceptance_mapping.rb`, `lib/gates/stop_gate.rb`. Stories M00-12/14/18.
Commits `e3817c8`, `7844bab`.

**The defect.** A ticked checkbox, a non-empty table cell, or any reference
matching `M\d{2}-\d{2}|ADR-\d{4}` satisfied a criterion. Those are things the
author writes about their own work, and the Autonomous Loop writes them for every
criterion. Separately, a Milestone Report containing only `Status:` passed the
Stop Gate — the one line the orchestrator needs and the one line that says
nothing about the Milestone.

**The fix.** A criterion is satisfied only when its evidence names something that
**exists**: a path in this repository, or a string its code contains — a test's
description, a constant, a check name. Documentation is deliberately not in that
corpus; a report justified by another document is still the author writing about
their own work. A deferral resolves only when the ADR file or the Story id it
names exists.

The Stop Gate now requires the eight sections
`docs/templates/MILESTONE_REPORT.md` declares, and a heading with nothing under it
is not one of them.

**What this found.** 45 criteria across 17 Story reports were asserted rather than
evidenced. Each now names the file or the test that proves it. Two were not just
missing a reference:

- **M00-06 #3** cited `spec/integration/dev_supervisor_spec.rb`, which does not
  exist, and described a kill test that was never written. The report now says
  what the spec actually asserts — that `bin/dev` is read structurally — and the
  gap is recorded under Pendências rather than described as a runtime test.
- **M00-10 #7** cited `bin/security-waivers --check` for the Dependency Gate,
  which is a different tool. It now names `bin/dependency-gate` and the three
  negatives added by this fix.

**Negatives:** `"refuses a claim with no reference at all"`, `"refuses a claim
naming a file nobody wrote"`, `"refuses a deferral to a decision nobody wrote"`,
`"accepts a claim quoting a test that exists"`, and for the report:
`"is refused, naming every section it left out"`, `"is refused when a section is
present but empty"`, `"is accepted once every section says something"`.

---

### M00-R17 — the Merge Gate looked for files no producer writes

`bin/merge-gate`. Story M00-11. Commit `874afde`.

**The defect.** `critical-zero` and `high-zero` — the two checks whose whole job is
to block a merge on blocking findings — read `tmp/security/report.json` and
`docs/implementation/*/review/*.json`. `config/ci/jobs.yml` writes
`tmp/security/security-report.json`, and the reviews are the Markdown of
`docs/templates/REVIEW_FINDINGS.md`. Neither path matched anything, both counted
zero, and both passed on every branch — including the ones with findings.

**The fix.** The security report is read from the path the pipeline writes, and
its `counts` field is used, so the gate and the report cannot disagree about what
"High" means. A missing or unreadable report fails, and one predating the
per-vulnerability format fails with that reason rather than counting zero. The
reviews are read through `Opanel::Gates::ReviewFindings`, the same reader the
Post-commit and Stop Gates use, for every `done` Story of every Milestone.

`--root` and `--security-report` were added so the gate can be exercised against a
scratch repository; both default to the canonical values.

**Negatives** (`spec/gates/ci_pipeline_spec.rb`): `"reads the report path the
pipeline actually writes"` (derived from `config/ci/jobs.yml`, so the two cannot
drift apart again), `"blocks when the scan never ran, rather than counting zero"`,
`"blocks on a report it cannot parse"`, `"blocks on a report that predates the
per-vulnerability format"`, `"counts a High the scan found"`, `"counts a blocking
finding in a Markdown review of a done Story"`, and `"passes when the same review
records the finding as resolved"`.

---

### M00-R10 — AF-06 and AF-07 checked approximations

`lib/gates/fitness_functions.rb`. Story M00-13. Commit `0a7b19a`.

**The defect.** AF-06 required the sink and the sensitive value on the same
physical line. A call with several arguments is not written that way, so

```ruby
Rails.logger.info(
  "sign-in attempt",
  api_key: params[:api_key],
)
```

passed — as did a `do` block and a hash continued below. AF-07 accepted the
Policy's name appearing anywhere in the Command's source: a comment saying
"TODO: route this through ServicePolicy", the name inside an error message, or a
constant nobody calls all cleared a mutation with no authorization at all.

**The fix.** AF-06 reads the sink's whole expression — until its brackets close,
or until the `end` of the block it opened, bounded at 25 lines — and applies the
redaction exemption to the line carrying the value rather than to anything else in
the same call. AF-07 requires the Policy to be constructed or called **and** the
action predicate invoked, or `authorize` to be passed the action, over code lines
only.

**Negatives** (`spec/gates/fitness_functions_spec.rb`): three multi-line sinks,
`"does not read past the end of the call it is examining"`, `"does not let a
redaction elsewhere in the call clear the value"`, three inert mentions of a
Policy, and `"still accepts the Policy invoked across two lines"`.

---

### M00-R09 — the security baseline carried no findings

`lib/gates/dependency_gate.rb`, `lib/gates/security_report.rb`,
`lib/gates/security_scanners.rb`, `bin/security`. Story M00-10. Commit `ebbf455`.

**The defect.** The Security Report was built from the gate's check list: one entry
per tool, `severity: "blocking"`. A check is not a vulnerability — it cannot name
the advisory, the package or the severity — so any consumer asking "how many
High?" read zero, including from a run that had found something. That is also why
M00-R17's Merge Gate could not have worked even against the right path.

The Dependency Gate asked `corpus.include?(name)` — a substring search over every
Story report and ADR in the repository. Any occurrence answered for the
dependency. Its lockfile check was the same kind of test: `lockfile.include?("rack")`
is satisfied by `rack-test`.

**The fix.** `bin/security` keeps each scanner's own machine-readable output under
`tmp/security/scanners/`, and `SecurityScanners` parses it into one finding per
vulnerability at the severity the scanner assigned. `severity` and `blocking` are
separate fields: static analysis is informational for M00 by M00-10's own
decision, and that is recorded as a policy with its reason rather than by quietly
downgrading a severity Brakeman set, which would make the report disagree with the
scanner. The report also carries `counts`, which is what the Merge Gate reads.

The Dependency Gate requires a **declaration** inside the section that exists for
it — "Dependências novas" in a Story Report, or an ADR — answering the questions of
Annex I §10.1: a full template block field by field, or a table row / line with
the section stating the licence and the lockfile. Both lockfiles are parsed rather
than searched.

**What this found.** M00-10 and M00-11 stated no licence and no lockfile for
`bundler-audit`, `brakeman` and `rexml`. The reports now say both. Nothing else in
the repository was unjustified, which is the result the substring check could not
have distinguished from the opposite.

**Negatives** (`spec/security/security_scan_spec.rb`): `"rejects the name appearing
in prose about something else"`, `"rejects a name inside a dependency section that
says nothing about it"`, `"rejects a template block whose fields are empty"`,
`"rejects a gem whose name is only a prefix of another gem's"`, `"rejects an npm
package that only appears inside another package's path"`, `"carries one finding
per advisory, with the severity bundler-audit assigned"`, `"counts Critical and
High, so the Merge Gate has a number to read"`, `"never carries the secret itself"`,
`"records a brakeman warning at its own severity, marked non-blocking for M00"`,
and `"treats a missing scanner result as a finding rather than as no findings"`.

---

### M00-R18 — the gate runner was incompatible with GNU mktemp

`bin/_gate_lib.sh`. Stories M00-11/12. Commit `874afde`.

**The defect.** `mktemp -t opanel-gate` is the BSD form, which appends the random
suffix itself. GNU coreutils — what the Ubuntu runner in `.github/workflows` has —
requires the template to end in at least three `X`s and exits non-zero without
them. `gate_begin` therefore exited 2 before a single check ran, on every gate, on
every push.

**The fix.** `mktemp "${TMPDIR:-/tmp}/opanel-gate.XXXXXXXX"`, which both
implementations accept.

**Negative** (`spec/gates/gate_scripts_spec.rb`): a stand-in `mktemp` on `PATH`
enforcing the GNU rule, under which `gate_begin`/`gate_finish` must complete — plus
a second example asserting the stand-in **rejects** the old form, so the test
cannot pass for the wrong reason.

---

### M00-R19 — closing evidence absent or not tied to the reviewed state

Exit Gate M00 and Stories M00-06/11/17. Commit `874afde` (the evidence format) and
this report.

**The defect.** `FIX_REPORT_01` claimed 651 examples with no pending; the last
metadata on disk recorded 563 with nine skips. The seven CI result files carried
no commit or branch, so a job name and `result: pass` were indistinguishable
between branches — or between a clean tree and a dirty one.

**The fix.** `gate_write_json` records `commit`, `branch`, `dirty` and
`finished_at` in every gate result, so an archived result names the code it
describes. The nine skips are explained below and are gone from the closing run.

**Negative** (`spec/gates/ci_pipeline_spec.rb`): `"names the commit, the branch and
whether the tree was dirty"`.

**About the nine skips.** They were not a masked failure: `bin/ci-job swarm-smoke`
is defined as `up / test / down`, so it leaves the lab **down**, and a full
`bin/test` run afterwards skips the nine `:swarm` examples with the explicit
reason M00-17 AC8 requires. Reproduced deliberately during this fix — the same run
after `bin/swarm-lab up` reports 0 pending. The ordering is now stated here; it is
a property of the job's contract, not a defect, and `bin/gate post-commit` refuses
evidence carrying skips either way.

---

## Files changed

| File | What changed |
|---|---|
| `lib/gates/swarm_lab.rb` | Effective endpoint resolution, exact-host + loopback matching, `InventoryUnknown` |
| `bin/swarm-lab` | Destination judged before any connection; `down`/`reset` refuse an unknown inventory; `status` reports it |
| `config/architecture/docker-lab.yml` | Structured `claimable_endpoints` |
| `bin/redact-artifacts` | Visual provenance, trace rewriting, `INERT_OPAQUE` split from `VISUAL` |
| `e2e/support/masked-capture.ts` | **new** — masking fixture and capture claims |
| `e2e/support/global-teardown.ts` | Resolves claims into digests before redacting |
| `e2e/smoke.spec.ts`, `e2e/gallery.spec.ts` | Import the masked `test` |
| `lib/gates/fitness_functions.rb` | AF-06 whole-call reading; AF-07 executable call |
| `lib/gates/dependency_gate.rb` | Section-scoped structured justification; real lockfile parsing |
| `lib/gates/security_scanners.rb` | **new** — per-vulnerability parsing of four scanners |
| `lib/gates/security_report.rb` | Findings and counts from the scanners' own results |
| `bin/security` | Keeps each scanner's machine-readable output |
| `bin/merge-gate` | Canonical review and security sources; `--root`, `--security-report` |
| `bin/_gate_lib.sh` | Portable `mktemp`; commit/branch/dirty in every result |
| `bin/test`, `bin/test-metadata` | Records the run's real selection |
| `bin/gate` | `frontend-tests` in `local`; both languages in the pre-commit `tests` item |
| `lib/gates/post_commit.rb` | Honest `covered_suites`; refuses skips |
| `lib/gates/acceptance_mapping.rb` | Evidence and deferrals must resolve |
| `lib/gates/stop_gate.rb` | Milestone Report completeness |
| `docs/implementation/M00/boundaries.yml` | M00-10 widened for `security_scanners.rb`, with the reason |
| 17 Story reports | Acceptance evidence now names a file or a test |
| 12 spec files | The negatives above |

## Tests and gates

Everything below was run against `e3817c8`, the last commit of this fix, with the
Swarm lab up. A second pass against the final commit — the one that adds this
report — is recorded in "Closing verification".

### Suites

| Comando | Resultado | Exit |
|---|---|---|
| `bin/test` | **723 examples, 0 failures, 0 pending** | 0 |
| `bin/test:js` (via `bin/ci-job frontend`) | 74 tests | 0 |
| `bin/test:e2e` (via `bin/ci-job e2e-critical`) | 9 tests | 0 |
| the seven specs this fix changed | **307 examples, 0 failures** | 0 |

`tmp/test-results/rspec-metadata.json` for that run:

```json
{"result": "pass", "type": "all", "scope": "all", "fast": false, "complete": true,
 "tests": 723, "failures": 0, "errors": 0, "skipped": 0,
 "commit": "e3817c85196684bdac3e196b0a8b31140ef78a87",
 "branch": "docs/agent-bootstrap", "dirty": true, "duration_ms": 368753}
```

**Zero skipped**, which is the number `CODEX_REVIEW_02.md` §4 found to be nine.
`scope`, `fast`, `complete` and `selected_paths` are the fields M00-R06 added, and
they are what makes "723 examples" a claim about the whole suite rather than a
label.

### Gates

| Gate | Resultado | Exit |
|---|---|---|
| `bin/gate local` | PASS — 9 checks, including the new `frontend-tests` | 0 |
| `bin/gate pre-commit` | PASS — the eight items of Annex I §12.1 | 0 |
| `bin/gate pre-commit` (planted secret staged) | **FAIL** — `secret-scan` red, `tests` red, and no certificate written | 1 |
| `bin/gate post-commit --story M00-12` | PASS — 8 checks | 0 |
| `bin/fitness` | PASS — AF-01..AF-10, each reported individually | 0 |
| `bin/pack validate` | PASS — 15 milestones | 0 |
| `bin/security --out tmp/security/security-report.json` | PASS — 7 checks | 0 |
| `bin/stop-gate M00` | **OK — the Milestone may stop**, all 10 checks PASS | 0 |
| `bin/stop-gate M99 --only acceptance` | `ok:false`, `"no tasks.json for M99"` | 0 (JSON mode) |
| `bin/swarm-lab up`/`down`, twice, each twice | 0 every time | 0 |

The planted-secret negative is worth one line of detail: the first attempt used
AWS's own documentation key, which gitleaks allowlists by default, and the gate
correctly stayed green. With a real-shaped credential the gate fails, the
workspace guardrail fails the related suite as well, and
`record_pre_commit_evidence` writes nothing — which is the M00-R05 fix from the
previous round still holding.

### CI jobs

`bin/ci-job <name> --out tmp/ci-results/<name>.json`, all ten required for merge:

| Job | Resultado | Duração |
|---|---|---|
| `static` | PASS | 5 646 ms |
| `unit` | PASS | 245 555 ms |
| `integration` | PASS | 38 267 ms |
| `contract` | PASS | 341 ms |
| `security-fast` | PASS | 123 966 ms |
| `frontend` | PASS | 2 123 ms |
| `migrations` | PASS | 827 ms |
| `setup` | PASS | 9 241 ms |
| `e2e-critical` | PASS | 4 135 ms |
| `swarm-smoke` | PASS | 20 720 ms |

Every result file names `commit: e3817c851…`, `branch: docs/agent-bootstrap` and
`dirty: true` — the M00-R19 fix. The three jobs `CODEX_REVIEW_02.md` §5 found
missing (`setup`, `e2e-critical`, `swarm-smoke`) are present and green.

### The five negative PR classes

M00-11's Required Tests, run as `spec/gates/ci_pipeline_spec.rb -e "a red check
blocks"` — each plants the failure and asserts the named job goes red:

```
  a red check blocks
    blocks a typecheck error
    blocks a lint error
    blocks a failing test
    blocks a detected secret
    blocks an invalid migration

5 examples, 0 failures
```

These are the five classes of AC2–AC6, proven against the jobs the pipeline
schedules. They are not five GitHub pull requests: opening those is an
outward-facing act the implementer should not take unasked, and what the criteria
name is the failure class, which is what the job decides.

### The Merge Gate

```
MERGE ALLOWED ONLY IF
  [ ] base-branch-current    HEAD is behind origin/main; rebase or merge the base branch before merging
  [x] ci-green
  [x] critical-zero
  [x] high-zero
  [x] migration-rollout-safe
  [x] rollback-known
  [x] story-status-consistent
  [x] documentation-current
  [x] pipeline-change-authorised
  [ ] required-approvals     the pull request is not reviewed
```

Eight of ten. `ci-green` and the two severity checks pass for the first time
*having actually read something* — before M00-R17 they passed by finding no file.
The two reds are the two controls the implementer cannot satisfy: `origin/main`
carries one commit this branch does not (`e6fd069`, the merge of PR #1), and there
is no approving review. Both are human decisions, and the gate refusing to treat
an unverifiable control as satisfied is the behaviour M00-11 AC8 asks for.

## Findings not fixed

None. All ten findings of `CODEX_REVIEW_02.md` are Critical or High and all ten
are addressed. The review recorded Medium 0 and Low 0, so nothing was deferred.

## Conflicts and blockers

No specification conflict was found. Two things are worth the reviewer's
attention rather than being silently absorbed:

1. **`.claude/settings.json` carries an uncommitted orchestrator change** (a
   `StopFailure` hook) that was already in the working tree before this fix
   began. `CLAUDE.md` forbids the implementer from modifying the orchestrator,
   its runners or its hooks while fixing review findings, so it was left
   untouched — which is why every evidence file below records `dirty: true`. It
   is the same pre-existing change `CODEX_REVIEW_02.md` §11 observed.
2. **The Merge Gate cannot pass here, by design.** `base-branch-current` requires
   `origin/main` to be fetchable and `required-approvals` requires a human
   review; neither is available to the implementer, and the gate correctly
   refuses to treat an unverifiable control as satisfied. The eight checks that
   *are* decidable from the workspace pass. Recorded below with the output.

## Closing verification

Repeated against `6e6322b`, the commit that adds this report — so the evidence
describes the state being handed to review rather than the state before it.

| Comando | Resultado | Exit |
|---|---|---|
| `bin/ci-job <name> --out …`, all ten required for merge | **10/10 PASS**, each naming `commit: 6e6322b9c` | 0 |
| `bin/test` | **723 examples, 0 failures, 0 pending**, `complete: true`, `skipped: 0` | 0 |
| `bin/gate pre-commit` (the hook, on the commit itself) | PASS — 8 checks | 0 |
| `bin/gate post-commit --story M00-14` | PASS — 8 checks | 0 |
| `bin/stop-gate M00` | **OK — the Milestone may stop**, all 10 checks PASS | 0 |
| `bin/merge-gate` | 8/10 — `base-branch-current` and `required-approvals` red, as above | 1 |

Individual CI durations at `6e6322b`: `static` 6 217 ms, `unit` 248 964 ms,
`integration` 37 597 ms, `contract` 339 ms, `security-fast` 126 684 ms,
`frontend` 2 183 ms, `migrations` 963 ms, `setup` 9 297 ms, `e2e-critical`
4 187 ms, `swarm-smoke` 21 562 ms.

Every result records `dirty: true`, for the single reason given under "Conflicts
and blockers": the pre-existing, uncommitted `.claude/settings.json` orchestrator
hook, which the implementer may not touch. `git status --short` at this commit
shows that file and nothing else.

---

# Attempt 03 — the same ten findings, re-proved at `ca7f2a3`

## Why there is a third attempt

Review 03 never returned a verdict. The Codex CLI stopped on its usage limit after
189,915 tokens, and the orchestrator recorded that as
`CODEX_REVIEW_EXECUTION_FAILED` rather than as a rejection (`f4d869a`) — an
execution failure is not a review.

`4d2fb44` then replaced that orchestrator with `tools/opanel-loop` and set M00
back to `fix_required` against the last verdict that exists, which is still
`CODEX_REVIEW_02`'s 1 Critical and 9 High. `ca7f2a3` raised `maxFixAttempts` from
3 to 4 so the new loop's first run would not spend the Milestone's last correction
on machinery nothing had exercised end to end.

So this attempt answers the same ten findings — not new ones — and the question it
has to settle is whether they are still answered **here**, on this branch, at this
commit.

## What changed in the code since attempt 02

Nothing.

```console
$ git diff --stat 6e6322b..HEAD -- bin/ lib/ app/ spec/ e2e/ config/ db/ \
    package.json package-lock.json Gemfile Gemfile.lock
$ echo $?
0
```

Empty. The four commits between `6e6322b` and `ca7f2a3` are the loop replacement
and its bookkeeping:

```console
$ git log --oneline 6e6322b..HEAD
ca7f2a3 chore(M00): give the fix budget a spare attempt before the new loop's first run
4d2fb44 feat(loop): run the whole Milestone inside Claude Code, without a second CLI
f4d869a chore(M00): record the third review stopping on the Codex usage limit
8e6701e docs(pack): record the closing verification of FIX_REPORT_02
```

`4d2fb44` adds `tools/opanel-loop/`, moves `scripts/agent-orchestrator.sh` and its
two runners to `scripts/legacy/`, empties the `Stop` hook from
`.claude/settings.json` and rewrites three documents. It touches no file under
`bin/`, `lib/`, `app/`, `spec/`, `e2e/`, `config/` or `db/`. The other three are
state and documentation.

**No new code was written in this attempt**, and none was needed: the ten fixes
are byte-identical to the ones attempt 02 verified. What this attempt adds is that
the evidence was produced again against the commit being handed over. "Green at
`6e6322b`" and "green at `ca7f2a3`" are different claims, and the second is the one
a reviewer of this branch can check.

## Per finding, re-proved at `ca7f2a3`

Each row is an execution at this commit, not a re-reading of attempt 02.

| Finding | Sev | What re-proves it here | Result |
|---|---|---|---|
| M00-R11 | Critical | `spec/integration/swarm_lab_spec.rb` — 41 examples, incl. the context, exact-host and loopback-resolution negatives; plus `bin/swarm-lab status` naming the endpoint it resolved from the current context | 0 failures, exit 0 |
| M00-R16 | High | same file — the four per-listing negatives and `"stops \`down\` before \`swarm leave\`"`; plus `bin/swarm-lab status` on a torn-down lab reporting `orphans unknown — …not a swarm manager` instead of `none` | 0 failures, exit 0 |
| M00-R02 | High | `spec/security/artifact_redaction_spec.rb` — 25 examples; `bin/ci-job e2e-critical` PASS | 0 failures, exit 0 |
| M00-R06 | High | `spec/gates/gate_scripts_spec.rb` — 68 examples, incl. the three narrowing negatives and the skip refusal; `bin/gate local` reporting `frontend-tests` as its own check | 0 failures, exit 0 |
| M00-R07 | High | `spec/gates/gate_scripts_spec.rb` + `spec/gates/stop_gate_spec.rb` — 89 examples; `bin/stop-gate M00` `acceptance` and `milestone-report` PASS | 0 failures, exit 0 |
| M00-R17 | High | `spec/gates/ci_pipeline_spec.rb` — 35 examples; `bin/merge-gate` `critical-zero`/`high-zero` green **having read** `tmp/security/security-report.json`, whose `counts` is `{"critical":0,"high":0}` | 0 failures, exit 0 |
| M00-R10 | High | `spec/gates/fitness_functions_spec.rb` — 61 examples; `bin/fitness` AF-01..AF-10 each reported individually | 0 failures, exit 0 |
| M00-R09 | High | `spec/security/security_scan_spec.rb` — 56 examples; `bin/security` writing a report with `findings`, `counts` and the four scanners' versions | 0 failures, exit 0 |
| M00-R18 | High | `spec/gates/gate_scripts_spec.rb` — the GNU-`mktemp` stand-in and the example asserting the stand-in rejects the old form | 0 failures, exit 0 |
| M00-R19 | High | all ten `required_for_merge` CI jobs run here, each result naming `commit: ca7f2a37d`, `branch: loop/replace-orchestrator`, `dirty: true`; `bin/test` complete with `skipped: 0` | 0 failures, exit 0 |

The seven spec files together are **307 examples, 0 failures** — the same 307 as
attempt 02, which is what an unchanged diff should produce.

## Commands, with exit codes

All run at `ca7f2a3` on `loop/replace-orchestrator`, with the Swarm lab up unless
noted.

### Suites

| Comando | Resultado | Exit |
|---|---|---|
| `bin/test` | **723 examples, 0 failures**, `complete: true`, `skipped: 0` | 0 |
| the seven spec files carrying the findings' negatives | **307 examples, 0 failures** | 0 |
| `bundle exec rspec spec/gates/ci_pipeline_spec.rb -e "a red check blocks"` | **5 examples, 0 failures** — typecheck, lint, test, secret, migration | 0 |

`tmp/test-results/rspec-metadata.json` for that run:

```json
{"result": "pass", "type": "all", "scope": "all", "fast": false, "complete": true,
 "tests": 723, "failures": 0, "errors": 0, "skipped": 0,
 "commit": "ca7f2a37d254391472d6fb20e6225d828f2ea696",
 "branch": "loop/replace-orchestrator", "dirty": true, "duration_ms": 375022}
```

### Gates

| Gate | Resultado | Exit |
|---|---|---|
| `bin/gate local` | PASS — 9 checks, `frontend-tests` among them | 0 |
| `bin/gate pre-commit` | PASS — the eight items of Annex I §12.1 | 0 |
| `bin/gate pre-commit` (synthetic credential staged) | **FAIL** — `tests` red, `secret-scan` red, `pre-commit evidence not recorded` | 1 |
| `bin/gate post-commit --story M00-14` | PASS — 8 checks | 0 |
| `bin/fitness` | PASS — AF-01..AF-10 individually | 0 |
| `bin/pack validate` | PASS — 15 milestones | 0 |
| `bin/security --out tmp/security/security-report.json` | PASS — 7 checks | 0 |
| `bin/stop-gate M00 --format text` | **OK — the Milestone may stop**, all 10 checks PASS | 0 |
| `bin/stop-gate M99 --only acceptance` | `ok:false`, `"no tasks.json for M99"` | 0 (JSON mode) |
| `bin/merge-gate` | 8/10 — the two reds are the two human controls, below | 1 |
| `bin/swarm-lab up`/`down`, twice | 0 on all four calls | 0 |

The planted-credential negative, in full, because GOAL condition 5 asks for a
controlled failure and not for the assertion that one would fail. A synthetic
AWS-shaped pair was staged in `config/planted_credential.rb`:

```
  tests                  FAIL  125509ms
      1) security scanning secret scan passes on this repository, tree and history
  secret-scan            FAIL  282ms
        secret-scan-staged     FAIL  35ms
            WRN leaks found: 1
  pre-commit evidence not recorded: the gate did not pass
gate:pre-commit: FAIL   EXIT=1
```

`tmp/gate/` held 49 certificates before the run and 49 after, and none for the
staged tree `4650f5db15cd650b64aecfdfc8daeb72cfc02728` — the M00-R05 fix from the
first round still holding. The file was unstaged and deleted immediately after;
`git status --short` shows only `docs/implementation/M00/review-state.json`.

### CI jobs

`bin/ci-job <name> --out tmp/ci-results/<name>.json`, all ten of
`config/ci/jobs.yml`'s `required_for_merge`:

| Job | Resultado | Duração |
|---|---|---|
| `static` | PASS | 5 464 ms |
| `unit` | PASS | 248 600 ms |
| `integration` | PASS | 37 633 ms |
| `contract` | PASS | 308 ms |
| `security-fast` | PASS | 126 331 ms |
| `frontend` | PASS | 2 173 ms |
| `migrations` | PASS | 845 ms |
| `setup` | PASS | 9 417 ms |
| `e2e-critical` | PASS | 4 473 ms |
| `swarm-smoke` | PASS | 21 392 ms |

Every result file names `commit: ca7f2a37d`, `branch: loop/replace-orchestrator`
and `dirty: true`.

### The Swarm Lab

```console
$ bin/swarm-lab status
swarm-lab: up
  engine        29.7.2 (Engine API 1.55)
  endpoint      unix:///Users/douglasprado/.docker/run/docker.sock
  swarm         active, 1 node(s)
  services      none
  orphans       none
```

`DOCKER_HOST` is unset here and the current context is `desktop-linux`, so the
endpoint printed is the one M00-R11 required: resolved through the CLI's own
precedence rather than assumed to be the local socket. After `down`, the same
command reports

```
  services      unknown
  orphans       unknown — Error response from daemon: This node is not a swarm manager…
```

which is M00-R16 in the field — a listing that failed says `unknown`, not `none`.

## Findings left open

None. All ten findings of `CODEX_REVIEW_02.md` are Critical or High and all ten
remain answered at `ca7f2a3`. The review recorded Medium 0 and Low 0, so there is
nothing deferred.

## Conflicts and observations

No specification conflict was found in this attempt. Three things belong to the
reviewer rather than to a silent decision:

1. **`dirty: true` in every artifact, for one file.** The dirty entry is
   `docs/implementation/M00/review-state.json`, which
   `review-state.sh <dir> fix-start` wrote to open this attempt and which the
   loop's own protocol leaves uncommitted until `fix-done`. The
   `.claude/settings.json` change that made attempt 02's artifacts dirty is gone:
   `4d2fb44` committed it. `git status --short` at the time of every run above
   shows that one file and nothing else.
2. **The Merge Gate is 8/10 and cannot be more.** `base-branch-current` reports
   HEAD behind `origin/main`; `required-approvals` reports `no pull requests found
   for branch "loop/replace-orchestrator"`. Both are human acts the implementer
   must not perform, and the gate refusing to call an unverifiable control
   satisfied is the behaviour M00-11 AC8 asks for. The eight decidable checks pass,
   including the three — `ci-green`, `critical-zero`, `high-zero` — that M00-R17
   made capable of reading anything at all.
3. **A stale path in `scripts/legacy/tests/agent-orchestrator-test.sh`.**
   `4d2fb44` moved the orchestrator into `scripts/legacy/` but its test still
   points at `$REPO_ROOT/scripts/agent-orchestrator.sh`, which no longer exists.
   Nothing runs it — no CI job, gate or spec references `scripts/` — so it is
   inert, and it is orchestrator machinery, which `CLAUDE.md` forbids the
   implementer from modifying while fixing review findings. Recorded, not touched.

## Closing verification (attempt 03)

Repeated against the commit that carries this report, so the evidence describes
the state being handed over rather than the state before it.

| Comando | Resultado | Exit |
|---|---|---|
| `bin/test` | **723 examples, 0 failures, 0 pending**, `complete: true` | 0 |
| `bin/gate post-commit --story M00-14` | PASS — 8 checks | 0 |
| `bin/stop-gate M00 --format text` | **OK — the Milestone may stop**, 10/10 PASS | 0 |

## Handoff

`review-state.json` is set to `ready_for_review` with `verdict` and all four
counts cleared. No verdict is claimed, `human_acceptance` is not declared, and M01
has not been started.
