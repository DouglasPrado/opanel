# M01 — Decisions

Append-only ledger of the arbitrations taken during the autonomous run of this
Milestone (`ADR-0007`). Each entry is the `arbiter` agent's decision block,
recorded verbatim, in a fresh context that never saw the implementer's reasoning.
The lead does not edit a verdict, summarise it, or argue with it — it acts on it.

---

## 2026-09-10 UTC — M01/M01-10

Situation: AC11 of `M01-10` requires a new architecture fitness function, whose only home (`lib/gates/fitness_functions.rb`) `guard-edit.sh` denies the running loop, so review finding F-2 leaves the Story with a normative criterion nobody may satisfy.

Evidence:  `docs/implementation/M01/stories/M01-10-node-registration-and-observation.md:24-30,82` (AC11 and its scope note); `docs/implementation/SPEC_CONFLICTS.md:317-327,335` (SC-20 `unresolved`, its three proposed paths); `tools/opanel-loop/hooks/scripts/guard-edit.sh:34,49-50,54-55` (deny on `^lib/gates/` and `^tools/opanel-loop/` while `.backlog-active` exists); `lib/gates/fitness_functions.rb:36,496-507` (the `ALL` registry a new checker must join; AF-01/AF-02 already present); `lib/gates/acceptance_mapping.rb:32-45,93-102` (a criterion is accounted when satisfied **or** deferred to an ADR/Story that resolves); `docs/decisions/ADR-0005-swarm-executor-in-process-for-m01.md:75-101,112-114` (three triggers; trigger 1 = second node; extraction Story is `M02-EXEC-SPLIT`; AF-01/AF-02, allowlist and no-exec remain the tested boundary); `docs/decisions/ADR-0007-autonomous-milestone-chain.md:66-79` ("`guard-edit.sh` keeps denying the running loop its own gates and plugin… gate maintenance is not a Milestone Story. Those Stories leave `tasks.json`."); `docs/implementation/M01/tasks.json` (no `M01-92`/`M01-93`/`M01-94`; `M01-10` at `fix_required`, line 204); `docs/implementation/M01/review/M01-10.md:49-62,171-176` (F-2, HIGH); `docs/implementation/M01/reports/M01-10.md:94,102` (AC11 unticked, evidence names only `SC-20`).

Verdict:   DEBT

Action:    Do not write the fitness function and do not touch `lib/gates/**` or `guard-edit.sh` in this run. The lead: (1) rewrites SC-20 in `docs/implementation/SPEC_CONFLICTS.md` from `unresolved` to `resolved`, recording that `ADR-0007` decides it — path 2 (a `M01-10` whitelist in `guard-edit.sh`) is refused, and paths 1 and 3 are unavailable because gate-maintenance Stories left `tasks.json`; the AF is human-directed loop maintenance performed outside an autonomous run, and updates the summary table (`unresolved` 1 → 0); (2) in `docs/implementation/M01/reports/M01-10.md` leaves AC11's box **unticked** and changes its evidence to name the decisions that account for it — `ADR-0005` (the trigger the AF mechanises) and `ADR-0007` (why no Milestone Story may carry it) — which is the deferral path `acceptance_mapping.rb` already accepts, not a claim of satisfaction; (3) carries F-2 into `M01`'s debt ledger and reproduces the reviewer's own words in the `bin/milestone-pr` body, flagged as work the human must do on the stack before M02 is planned. This releases AC11 only: F-1 remains Critical and still blocks `M01-10`.

Reason:    FIX is not available to me — the smallest change that closes AC11 is an edit to `lib/gates/fitness_functions.rb`, and authorising that (directly or by whitelisting the Story in the guard) is on my refusal list and is the exact relaxation `ADR-0007` §"What does not change" forecloses; a gate is never editable by the run it judges. BLOCK is disproportionate: nothing stacked on M01 builds on this checker. The state it would catch — a second registered `Node` — is unreachable in M01, where enrolment is out of scope (`M08-01`..`M08-03`) and only the bootstrap Manager exists, and `ADR-0005`'s compensating controls (AF-01, AF-02, the eleven-operation allowlist, no exec primitive, redaction) are implemented and tested and are untouched by this deferral. What is genuinely lost is the mechanical deadline: until the AF exists, trigger 1 is prose again, exactly the failure mode `ADR-0005:90-96` set out to prevent — so it is recorded as debt with a named inheritor rather than quietly dropped.

Inherits:  M02 — with `M02-EXEC-SPLIT`; the AF must exist before any Milestone makes a second `Node` registrable (`M08-01`..`M08-03`), and a reviewer finding the executor in-process past trigger 1 without it has a Critical finding per `ADR-0005:108-111`.
