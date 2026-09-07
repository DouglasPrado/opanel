---
title: "The CI pipeline"
type: "engineering-convention"
---

# The CI pipeline

**The pipeline is `config/ci/jobs.yml`.** The workflows in `.github/workflows/`
only schedule it — they contain no test command of their own. Anything CI runs
can therefore be run here, by name:

```bash
bin/ci-job static              # one job
bin/ci-job --stage pr          # every job of a stage
bin/ci-job --list              # what exists
bin/ci                         # the PR stage, via Rails' own runner
```

That is the whole point of the arrangement. "It only fails in CI" is nearly
always a difference between what CI runs and what somebody ran locally, and
there is no second definition here for the two to disagree about.

## Cadence — Annex D §20

| Stage | Jobs | When |
|---|---|---|
| **PR** | `static` `unit` `integration` `contract` `security-fast` `frontend` `migrations` `setup` | every pull request |
| **Merge** | the PR stage, plus `e2e-critical` `swarm-smoke` | pull requests targeting `main` |
| **Nightly** | `swarm-full` `build-corpus` `load-smoke` `chaos-subset` | 03:00 UTC |
| **Release candidate** | `e2e-critical` `performance` `security-deep` `restore-upgrade` | `v*-rc*` tags |

The nightly and release-candidate jobs are **declared and empty**. M00 builds the
harness; the suites arrive with the Milestones that own them, and each empty slot
names which one (`populated_by`). An empty slot reports `empty` — never `pass`.
A job that says green while running nothing is a false statement about the
build, and worse than a missing check because nobody goes looking for it.

## Job names are a contract

The Merge Gate requires jobs **by name**, from `required_for_merge` in
`config/ci/jobs.yml`. Not "most checks passed", not "nothing is red": each named
job, present and passing. A job that vanished from the run fails the gate, so
deleting the job that was failing does not unblock a merge.

Renaming or removing one is a pipeline change. See below.

## The gates

| Gate | Command | Decides |
|---|---|---|
| PR Gate | the `pr-gate` job | may this pull request be considered at all |
| Merge Gate | `bin/merge-gate` | may this be merged (Annex I §15.2) |

`bin/merge-gate` executes the §15.2 checklist rather than displaying it: every
item runs a command and uses its exit code. The pull-request template shows the
same list so a human reads it, but **ticking a box there proves nothing** and the
gate does not read it — an agent would tick every box.

What the gate cannot verify, it refuses. Required approvals live in GitHub
branch protection; without `gh` the gate says it could not check them and exits
non-zero. Missing evidence is never read as consent.

## Evidence — Annex D §24

Every job writes `tmp/ci-results/<job>.json` (name, result, duration, and the
reason for each failed check) and archives it with the test and security reports
under `evidence-<job>-<run-id>-<attempt>`, kept 30 days.

Artifacts are **redacted before** they are uploaded, never after
(`bin/redact-artifacts`, Annex C §17.1). Traces, screenshots and videos record
whatever was on screen and on the wire: that is why they are useful, and why
they cannot be published unexamined. A hit that cannot be masked deletes the
artifact and fails the step — losing a diagnostic is recoverable, publishing a
credential is not.

Archiving runs on `always()`. A red run is the one worth reading.

## Flaky rate — Annex D §20.1

```bash
bin/flaky-rate tmp/history --format json
```

Flakiness is only visible across runs: one result file cannot show that a test
passed once and failed once. The nightly `flaky-rate` job downloads the last 40
archived runs and reports the rate and the top offenders.

It measures. **It does not retry.** Retrying until green converts a real
intermittent bug into a slower pipeline and a suite nobody believes. What a flaky
test gets is a quarantine with an owner and a deadline — see
[`flaky-tests.md`](flaky-tests.md). Declared quarantines are listed alongside the
observed offenders, so the two can be read against each other.

## Databases

Every job gets its own ephemeral PostgreSQL service container, and
`bin/test --parallel` gives each worker its own database (`opanel_test`,
`opanel_test2`, …). Two jobs cannot truncate each other's tables — a collision
that presents as a flaky test and is not one.

## Changing the pipeline

A change to `.github/`, `config/ci/`, `config/architecture/`, `config/security/`,
`lib/gates/` or the gate scripts changes how the repository judges every other
change. It may not ride along inside an unrelated Story (Annex I §21.2).

Two things enforce that:

- `bin/merge-gate`'s `pipeline-change-authorised` check fails unless a commit in
  the range names the Story or ADR that authorises it (`M00-11`, `ADR-0002`);
- `.github/CODEOWNERS` requires a human review of those paths.

A gate is never edited to make a Story pass. Failing one means fixing the
implementation, or opening an explicit, dated, owned waiver
(`config/security/waivers.yml`).

## No production credential

CI holds none, and none may exist in the workspace at all (Annex C §21,
Annex H §3.2). `SECRET_KEY_BASE` in the workflows is a fixed placeholder that
exists so the test environment boots; `bin/workspace-guardrail` runs inside
`security-fast` and fails on a credential shape bound for a production
destination.
