# ADR-0006 — Incremental Story gates and bounded reviews

Date: 2026-09-10
Status: accepted for the operator-requested gate performance work

## Problem

Every Story's local gate compared with main, repeatedly testing the accumulated
Milestone. A single mutable evidence file lost earlier suite results, while
report/task bookkeeping invalidated otherwise identical test inputs. Review
turn counts did not constrain an individual reviewer spending an hour in a turn.

## Decision

- `tasks.sh set ID in_progress` records HEAD once in `tmp/gate/story-bases/ID.json`.
  Retries retain that base. Local gates use it, including unstaged new files and
  deletions. Without a saved base they conservatively retain branch scope.
  Explicit `OPANEL_GATE_BASE` remains supported; CI retains branch scope.
- A Story requires its mapped related specs. When a declared test class has no
  mapped spec, run the entire class conservatively. CI/merge still run the full
  declared suites. No named gate, negative assertion, scanner rule or threshold
  is removed. This specializes the related-tests policy of Annex I §11–14.
- Every test execution keeps its own JSON record with the selected spec files,
  input digest, environment digest, timestamps, result and counts. Inputs are
  captured before execution and checked afterwards. Only reports, review prose
  and tasks.json are administrative; Story requirements and boundaries count.
- Local executions can reuse passing evidence for the requested files and same
  inputs/environment within one hour. Skips, empty runs, unstable inputs and
  newer failures do not qualify. Explicit seeds, `--force` and CI always execute.
  Post-commit combines passing selections for the committed input digest.
  Legacy metadata remains readable; hook evidence remains tied to the full tree.
- Gate/scanner probes use private repositories and Git indexes, with the real
  tools and configuration. Dependencies are shared; probes never edit them.
- Story reviewers have Read/Grep/Glob only and return findings to the lead.
  Hooks start a 300-second deadline and stop further tool processing once it
  expires. This is enforcement at tool boundaries, not an out-of-process timer
  interrupting model inference. Incomplete review cannot authorize DONE.
- The fourth automatic Story attempt is refused and recorded as blocked.
  Gate/plugin maintenance is ordinary authorized work outside a backlog run;
  active builders cannot modify their own gates or plugin.

## Consequences

The runner still invokes the pre-commit hook on an amend, but tests can reuse
valid evidence across administrative changes. Review independence and blocking
findings remain mandatory. Deleting local evidence or base records only makes
validation broader/more expensive; it does not grant completion.

Hook payloads follow the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks).
