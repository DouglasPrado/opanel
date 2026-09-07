# Milestone Report — M00 Foundation

Status: READY_FOR_REVIEW

- Milestone: `M00` — Foundation
- Branch: `docs/agent-bootstrap`
- Head: `f32a344`
- Date: `2026-09-06`
- Implementer: Claude (IMPLEMENTER role — this is **not** an independent review
  and carries no verdict)

M00 builds no Opanel domain entity. It builds the machinery every later
Milestone is judged by: the runtime, the harnesses, the gates, and the loop's
own memory.

> **This report describes the first implementation pass.**
> `CODEX_REVIEW_01.md` returned `NOT_ACCEPTED` (Critical 1, High 15) against
> `2a38d11`. Every one of those findings is answered in
> [`FIX_REPORT_01.md`](FIX_REPORT_01.md), which carries the fix, its evidence and
> the re-run of every suite and gate. Read the two together: the numbers below
> were measured before the fix, and the ones that changed are restated there.

## Stories

18 required, 18 `done`, 0 blocked. One commit per Story, plus three
bookkeeping commits and one fix.

| Story | Título | Commit |
|---|---|---|
| M00-01 | Repository and Rails skeleton | `d85418b` |
| M00-02 | Inertia + React + Vite integration | `86163d7` |
| M00-03 | Solid Queue and the job runtime | `2d1d290` |
| M00-04 | Frontend toolchain and HMR | `7241a05` |
| M00-05 | Component library import and inventory | `a999b21` |
| M00-06 | Reproducible local development environment | `b8a5f82` |
| M00-07 | Backend test harness on real PostgreSQL | `d10e688` |
| M00-08 | Component and browser test harnesses | `97eabb3` |
| M00-09 | Lint, format and typecheck toolchain | `202c052` |
| M00-10 | Security scanning baseline | `e12d5c8` |
| M00-11 | CI pipeline with PR and Merge gates | `e256b12` |
| M00-12 | Local, pre-commit and post-commit gate scripts | `65c3f0f` |
| M00-13 | Architecture fitness functions AF-01..AF-10 | `0214fb4` |
| M00-14 | Autonomous Development Loop scaffolding | `11c9a16` |
| M00-15 | Structured logging, correlation IDs and health endpoints | `524e9ed` |
| M00-16 | Environment configuration and secrets management | `4070dab` |
| M00-17 | Disposable Docker/Swarm Lab harness | `f230511` |
| M00-18 | ADR, Story Report and Milestone Report templates | `319aa15` |

Every Story has a report in `reports/` mapping its acceptance criteria to
evidence, and a self-review in `review/`.

## Quality

Commands run on `f32a344`, with their exit codes.

| Comando | Resultado | Exit |
|---|---|---|
| `bin/test` (whole suite, lab image present) | **554 examples, 0 failures, 0 pending** | 0 |
| `bin/gate local --story M00-12` | PASS — 8 checks | 0 |
| `bin/gate pre-commit` | PASS — 8 checks, 62.8 s on the full-Milestone diff | 0 |
| `bin/gate pre-commit` (staged secret planted) | **FAIL** — `secret-scan` red | 1 |
| `bin/gate post-commit --story M00-12` | PASS — 8 checks | 0 |
| `bin/fitness` | PASS — 10 functions, each reported individually | 0 |
| `bin/pack validate` | PASS — 15 milestones | 0 |
| `bin/security` | PASS — secret scan, bundler-audit, npm audit, Brakeman | 0 |
| `bin/ci-job --stage pr` | PASS — 7/7 jobs | 0 |
| `bin/swarm-lab up`/`down` ×2 | 0, 0, 0, 0 | 0 |
| `bin/stop-gate M00` | **OK — the Milestone may stop**; all 10 checks PASS | 0 |
| `bin/stop-gate M99 --only acceptance` | `ok:false`, `"no tasks.json for M99"` | 0 (JSON mode) |

Per-check detail is in the transcript. The negative cases — one per Pre-commit
item, one per fitness function, one per pack rule, five per CI failure class —
are in `spec/gates/` and run as part of the suite above.

### Test classes

| Classe | Estado |
|---|---|
| unit | green |
| integration (real PostgreSQL) | green |
| request | green |
| policy | **empty, declared** — the first entity with an owner arrives in M01 |
| contract | **empty, declared** — the first external contract arrives in M02 |
| security | green |
| frontend (Vitest) | green |
| e2e (Playwright) | green — `smoke`, `gallery` |
| docker/swarm (real Engine) | green — 15 examples, Docker 29.7.2, Engine API 1.55 |

`policy` and `contract` are empty directories with a README saying what belongs
there and which Milestone brings the first one. They are declared because
`lib/gates/suite_types.rb` names them and the pipeline schedules them: a type
with nowhere to live fails the job that runs it, which is how it was found.

## Findings

From the 18 self-reviews. These are implementation self-review findings, **not**
an independent review verdict.

| Severidade | Abertos | Resolvidos na própria Story |
|---|---|---|
| Critical | 0 | 0 |
| High | 0 | 2 |
| Medium | 6 | 11 |
| Low | 12 | 28 |

`Critical = 0` and `High = 0`.

The **six open Medium findings** are all accepted with their reasoning recorded,
and all six are things a reviewer should look at rather than take on trust. Four
of them are a constraint the environment or the imported library imposed, not a
preference:

| Finding | O quê | Por que aceito |
|---|---|---|
| M00-17 F-2 | Three test-only files added to the Tier-0 `docker_boundaries` list | The harness is what makes the executor testable at all; it has no route and no application caller. **A fourth entry should stop and write the ADR** — at that point the list has drifted from "the executor" to "whatever needs Docker". |
| M00-12 F-1 | Pre-commit secret scan reads the staged diff, not the whole tree | That is the question a pre-commit gate asks; CI still scans the whole tree and the history on every push. The alternative was a 13-second hook, which Annex I §12.1 names as the cause of bypasses. |
| M00-08 F-2 | `style-src 'unsafe-inline'` | Radix writes to `element.style` to position floating elements, and a nonce cannot authorize a CSSOM mutation. `script_src` stays `'self'` outside development — inline script is code execution, inline style is presentation. |
| M00-05 F-2 | `exactOptionalPropertyTypes` and `noUncheckedIndexedAccess` dropped project-wide | Six errors, all inside imported components. Editing vendored files is drift nobody reconciles; per-directory options need project references and declaration emit. `strict` itself is on. **The clearest candidate for revisiting**, because the cost falls on Opanel's own code. |
| M00-05 F-3 | Three WCAG 2.2 AA violations baselined | All upstream and unreachable from here. The baseline can only shrink, is enforced in both directions, and Opanel's own pages carry no baseline at all. |
| M00-03 F-1 | Solid Queue runs `async` on macOS instead of `fork` | `fork` segfaults inside libpq on arm64-darwin; four strategies were tried and the reproduction contains no Rails and no Opanel code. Linux and CI keep `fork`. |

Two High findings were found and fixed inside their own Story: the missing
`vite_react_refresh_tag` (M00-06 — development loaded the page and never mounted
React, silently) and the nested `bin/test` overwriting the outer run's evidence
(M00-12 — a 508-example run recorded itself as one example, and the post-commit
gate reads that file as proof the suite ran).

Two more of the same class were found by the final evidence run and fixed:

- `a0373c2` — the `--no-verify` checker matched nothing, because `git grep -E` is
  POSIX ERE and `\b` is a literal `b` there. A checker that quietly stops
  checking is worse than one that is too loud.
- `f32a344` — two Stop Gate examples asserted the exit-code contract using M00's
  own *missing* `MILESTONE_REPORT.md`. Writing this report turned a "must be red"
  case green, which is a test passing for a reason unrelated to what it claims.
  They now ask about a Milestone that does not exist.

Both were caught by running the whole suite rather than the changed subset, which
is the argument for the `unit` job running `:slow` on every push.

## Resultado funcional

- A clean clone runs `bin/setup` and `bin/dev` and serves a rendered Inertia
  page. Verified by cloning to `/tmp/opanel-clone`, running the documented single
  command, and driving the result in a real browser — which is what found the two
  development-mode defects nothing else could.
- `GET /up` reports application, PostgreSQL and queue separately, and answers 503
  with a classified cause when a dependency is down.
- Logs are one JSON object per line with the reserved correlation fields, and a
  `request_id` from the HTTP edge reaches the job that request enqueued.
- Jobs run on Solid Queue across six declared queues.
- A disposable Swarm lab comes up, hosts a Service, reports its Tasks, and comes
  down — and refuses to touch a daemon that is not the lab.
- `bin/ci-job --stage pr` runs the same seven jobs GitHub runs.
- `bin/pack next M00` and `git log` rebuild the loop's state without the
  conversation.

## Blocked

None. No Story is `blocked`; no `BLOCKERS.md` was needed.

Two things were worked around rather than blocked, both recorded in their Story
reports: `docker pull` was unreachable from this environment (the lab image is
therefore configurable, and the suite skips explicitly when it is absent), and
Solid Queue's fork supervisor segfaults on macOS (`bin/jobs` uses `async` on
Darwin, `fork` elsewhere, with the reproduction in the script).

## Dependências novas

| Dependência | Story | Justificativa |
|---|---|---|
| `rspec-rails`, `factory_bot_rails`, `parallel_tests`, `rspec_junit_formatter` | M00-07 | The declared test runner (SC-03) and the harness the pipeline consumes. |
| `bundler-audit`, `brakeman` | M00-10 | Required by that Story's acceptance criteria; both maintained inside the Rails security ecosystem. |
| `rubocop-rails-omakase` | M00-09 | The Rails default ruleset; project rules specialize it in `.rubocop.yml`. |
| `rexml` | M00-11 | `bin/flaky-rate` reads JUnit output back, which needs the per-test outcomes only the XML carries. Ruby's own parser, pure Ruby, stdlib until 3.0 — the line is the unbundling catching up. Alternatives evaluated: hand-rolled parsing (fragile against a format we do not own) and nokogiri (present transitively; depending on a transitive gem directly is how a dependency disappears under you). |

Each is pinned in `Gemfile.lock`. gitleaks is a binary, installed by `bin/setup`
and by CI; its absence is reported as a setup failure, never as a pass.

## Conflitos de especificação

Recorded in `docs/implementation/SPEC_CONFLICTS.md`. Resolved during M00: SC-01
(Inertia, not a separate frontend), SC-02 (Solid Queue), SC-03 (test runners
delegated to the pack), SC-07 (the component library, closed by M00-05).

**SC-04 and SC-08 remain open and block M01, not M00.** Neither was resolved
here: M00 implements no domain entity, so neither could be decided by
implementation, and deciding one silently is exactly what `AGENT_RULES`
forbids. They need a decision before M01-01 starts.

## Human acceptance requested

The human is asked to accept:

1. **The six open Medium findings above**, and in particular the two that touch a
   security boundary: the Tier-0 widening of `docker_boundaries` (M00-17 F-2) and
   `style-src 'unsafe-inline'` (M00-08 F-2).
2. **The two TypeScript strictness flags dropped project-wide** (M00-05 F-2).
   This is the one whose cost falls on code Opanel has not written yet, so it is
   the cheapest to revisit now and the most expensive to revisit later.
3. **`policy` and `contract` shipping as declared-empty suites.** They report
   zero examples, which is honest today, but it is the kind of thing that stays
   empty quietly.
4. **That M00 is engineering infrastructure only**, and that the first thing the
   next Milestone needs is a decision on SC-04 and SC-08.

Independent review has not been performed. This report is the implementer's
account of its own work; `review-state.json` is set to `ready_for_review` and
control returns to the orchestrator. M01 has not been started.
