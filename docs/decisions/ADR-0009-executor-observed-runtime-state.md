# ADR-0009 — The Swarm Executor returns observed runtime state in a dedicated `observed` field, as a normalized `RuntimeObservation`, and addresses owned resources by ownership label

Date: 2026-09-11
Status: accepted by the autonomous run (ADR-0007), pending human review in the Milestone's Pull Request

## Problem

`M01-17`'s Network Reconciler is red against the Swarm lab on all five examples
(`spec/integration/network_reconciler_lab_spec.rb`), and the arbiter's fourth-round
diagnosis (`docs/implementation/M01/DECISIONS.md`, 2026-09-11 — M01/M01-17) is that the
reconciler completes and creates nothing observable. Every remaining Story in the
Milestone — `M01-18` through `M01-23` (`docs/implementation/M01/tasks.json:351-410`) —
is downstream of it.

Three failures, one missing contract:

1. `app/reconcilers/network_reconciler.rb:126,128` read
   `result.safe_metadata.dig(:network_data)`. `app/executors/swarm_executor.rb:169-175`
   (`do_inspect_network`) returns `ExecutionResult.applied(command, ids:, name:, driver:)`,
   and `app/executors/execution_result.rb:61-64` has no such key. `actual` is `nil` on
   every path, always — so `Opanel::NetworkDiff.compute` sees `actual: nil` and answers
   `CREATE` forever, and `network_reconciler.rb:201` never reaches `READY`.
2. `swarm_executor.rb:170` issues `GET /networks/<environment ULID>`, because
   `network_reconciler.rb:116,180` pass `network.environment.id` as `resource_id`. That is
   neither a Docker network id nor its name, so the inspect 404s no matter what the daemon
   holds. The same shape makes `do_remove_network`/`do_remove_service`
   (`swarm_executor.rb:151-157,177-183`) answer `NOOP(absent: true)` for a resource that
   exists — a remove that reports convergence without removing anything.
3. `lib/opanel/ownership.rb:119` reads `dig("Spec", "Labels")`, which is the Swarm
   **service** shape. `GET /networks/{id}` returns `Labels` at the top level, so
   `managed_by_platform?` answers `false` for every network the platform itself creates —
   the exact gate at `network_reconciler.rb:201` and `network_diff.rb:60-63`.

The approved contract does not decide this. `docs/architecture/07-internal-control-plane.md`
§20.2 declares `ExecutionResult { commandId, outcome, observedRuntimeVersion,
runtimeResourceIds, safeMetadata, errorCode? }` — a version, a list of ids and a metadata
bag, and no field for an observed resource. §11.3 steps 3 and 8 nevertheless *require* the
reconciler to inspect Actual State and to re-inspect after acting, and §11.4 requires it to
tell `NOOP` from `CREATE` from `BLOCKED` — none of which is decidable from a version and an
id list. `safe_metadata` cannot be the channel: `execution_result.rb:14-18` states its
contract ("never a spec, never a body, never an error message verbatim") because
`swarm_executor.rb:402-418` writes that bag into the forensic log line. There is today no
correct place for `inspect_network` to put the JSON the reconciler must read. That is a
contract change across the one privileged boundary, which `docs/AGENT_RULES.md`
("Documentation", "Specification Conflicts") sends to an ADR rather than to a fix round.

No accepted ADR decides it. `ADR-0001` fixes the label namespace, `ADR-0002` the identifier
strategy, `ADR-0005` keeps the executor in-process for M01 and states that the future
extraction is "troca de transporte atrás do contrato `ExecutorCommand`/`ExecutionResult`" —
a constraint this record respects rather than contradicts. `docs/implementation/SPEC_CONFLICTS.md`
records SC-19 (the process boundary), not this. Nothing here is superseded.

That three unit examples in `spec/unit/network_reconciler_spec.rb:28,51` are green while
stubbing `safe_metadata: { network_data: nil }` — a key no executor ever writes — is why
this was not caught by the suite.

## Decision

### 1. `ExecutionResult` gains one field: `observed`

`app/executors/execution_result.rb` adds a seventh field, defaulting to `nil`:

```ruby
ExecutionResult = Data.define(:command_id, :outcome, :observed_runtime_version,
  :runtime_resource_ids, :safe_metadata, :error_code, :observe_before_retry, :observed)
```

`observed` is `nil`, or an `Opanel::RuntimeObservation`. It is an **extension** of doc 07
§20.2, not a replacement: every field the approved contract names keeps its meaning, and
`safe_metadata` keeps its own — identifiers, versions, counts and flags, never a body.

The factory methods `applied` and `noop` take `observed:` as an explicit keyword **before**
`**metadata`, so it is never absorbed into the bag:

```ruby
def applied(command, version: nil, ids: [], observed: nil, **metadata)
def noop(command, version: nil, ids: [], observed: nil, **metadata)
```

`conflict`, `retryable`, `failed` and `unknown` never carry an observation: nothing was
read. A metadata key literally named `observed` becomes impossible; that is intended.

### 2. `Opanel::RuntimeObservation` — the shape

New file `lib/opanel/runtime_observation.rb` (in `lib/opanel/` because its consumers
`Opanel::Ownership` and `Opanel::NetworkDiff` live there; `app/` may depend on `lib/`, not
the reverse):

```ruby
Opanel::RuntimeObservation = Data.define(:kind, :runtime_id, :name, :labels, :version, :attributes)
```

| field | type | rule |
|---|---|---|
| `kind` | String | closed set: `"service"`, `"network"`, `"node"`. Anything else raises. |
| `runtime_id` | String | the Engine's own id — `ID` for services and nodes, `Id` for networks. Never a platform id. |
| `name` | String | the Engine's `Name` / `Spec.Name`. |
| `labels` | `Hash<String, String>` | **flattened**: `Spec.Labels` for services and nodes, top-level `Labels` for networks. `{}` when absent, never `nil`. |
| `version` | Integer or `nil` | `Version.Index`, the CAS baseline. |
| `attributes` | `Hash<String, String\|Integer\|Boolean\|nil>` | a per-kind allowlist, flat, no nesting. |

The `attributes` allowlist, complete for today:

- `network`: `driver`, `scope`, `attachable`, `internal`
- `service`: `image`, `replicas`, `mode`
- `node`: `role`, `availability`, `state`, `hostname`, `advertise_address`

Every value is a JSON primitive. The observation must survive a JSON round trip unchanged,
because `ADR-0005` commits the executor's extraction to being a transport swap behind this
contract, and a value object that does not serialize would make that swap a redesign.

Adding a field to the allowlist is an ordinary Story change. Adding one whose value can
carry secret material is not: container `Env` **values**, registry auth, and the contents of
Swarm secrets or configs are never carried. When a future Story needs env drift detection it
carries sorted env **keys** plus a SHA-256 digest over the full `KEY=VALUE` set, never the
values, and ships a redaction test with it.

`RuntimeObservation#inspect` and `#to_s` return a redacted summary
(`#<Opanel::RuntimeObservation network 3f2a… labels=5 attrs=4>`), so an observation
interpolated into a log line or an exception message by accident cannot dump a body.

### 3. Who produces it, and when

Normalization happens **only** inside `SwarmExecutor`. It is the one component that speaks
Engine JSON, and after this ADR it is the only one that parses it: no reconciler, diff,
command, policy or predicate outside `app/executors/` may index into an Engine response
shape (`"Spec"`, `"Labels"`, `"ID"`, `"Id"`, `"Version"`, …).

`observed` is non-`nil` **exactly when** the executor read a full resource body during the
call:

- `inspect_service`, `inspect_network`, `inspect_node` — on `APPLIED`, always. An inspect
  that answers `APPLIED` with `observed: nil` is a defect, and the contract spec asserts it.
- the adoption `NOOP` of `create_service` / `create_network` (`swarm_executor.rb:112-114,160-161`),
  which already holds the body it found by label.

Every other operation returns `observed: nil`. Mutations may set it when they read the
resource back anyway, but no caller may depend on that: doc 07 §11.3 step 8 requires the
reconciler to re-inspect regardless, and a mutation's own echo is not an observation.

`outcome` never depends on `observed`. An observation is an input to the diff, not to the
result classification: a `NOT_FOUND` inspect stays `FAILED` with `error_code: "NOT_FOUND"`
and `observed: nil`, which is what `converged_by_observation?` (`swarm_executor.rb:387-396`)
and `retry_after_observing` already read.

### 4. Ownership and diff consume the observation, not Docker JSON

- `Opanel::Ownership.managed_by_platform?` takes a `RuntimeObservation` and reads
  `observation.labels`. It no longer accepts a raw Hash, and `ownership.rb:119`'s
  `dig("Spec", "Labels")` is deleted. Two callers and three unit examples change with it;
  a dual-shape predicate is not written, because keeping the Docker-shape branch alive is
  keeping the bug alive.
- `Opanel::NetworkDiff` compares `actual.name` and `actual.labels` (`network_diff.rb:51,69`
  today reach into `dig("Spec", "Name")`).
- `log_anomaly` / `resource_type_for` (`ownership.rb:182-201`) read `observation.kind`,
  `runtime_id` and `name`.

### 5. How an operation names its target

An observation of the wrong resource is not an observation, so the addressing rule is part
of this contract. `ExecutorCommand#resource_id` means one of exactly two things, fixed per
operation:

| operation | `resource_id` is | how the executor reaches the daemon |
|---|---|---|
| `create_service`, `inspect_service`, `update_service_spec`, `remove_service`, `service_logs`, `list_tasks` | the **external** service id (`svc_01…`, ADR-0002) | filter by label `com.opanel.service_id=<resource_id>` → runtime id → path |
| `create_network`, `inspect_network`, `remove_network` | the **external** environment id (`env_01…`) | filter by label `com.opanel.environment_id=<resource_id>` → runtime id → path |
| `inspect_node` | the Swarm node id | direct path — nodes are not created by the platform and carry no ownership label |
| `list_nodes` | unused; callers pass `"cluster"` | — |

Consequences of the rule, all intended:

- The only strings interpolated into an Engine path are ids the executor itself read from
  the Engine in the same call, plus the node id. `identifier()` (`swarm_executor.rb:274-279`)
  still validates both.
- `find_by_label`'s prefix-sniffing branch (`swarm_executor.rb:296-307`, `if validated_id.include?("_")`)
  is deleted: `resource_id` is always already in the external form the label carries.
- The platform can no longer mutate a resource that does not carry its ownership labels,
  by construction rather than by check. A label lookup that finds nothing answers:
  `inspect_*` → `FAILED` / `NOT_FOUND`; `remove_*` → `NOOP(absent: true)`; `update_service_spec`
  → `FAILED` / `NOT_FOUND`.
- It costs one extra Engine round trip per owned operation. That is the price of never
  addressing a resource by a name the platform guessed.

## Alternatives rejected

**Put the body in `safe_metadata` under `:network_data`.** The one a reasonable engineer
picks — the reconciler already reads that key, and it is a one-line change in
`do_inspect_network`. Rejected: `safe_metadata` is the bag `swarm_executor.rb:402-418`
writes into the forensic log line, and `execution_result.rb:14-18` says in its own words
that it never carries a body. Putting a service inspect there makes leaking `ContainerSpec.Env`
a matter of one careless log statement, and silently repeals a documented contract to
save a value object.

**A new field carrying the raw Engine JSON (`observed_body`).** Cheap, and it keeps the
executor dumb. Rejected: it spreads Engine shapes across the domain, and the cost of that
is already measurable — `ownership.rb:119` is exactly this mistake, a predicate that reads
the service shape and silently answers `false` for networks. It also carries `Env` values
into the domain by default, which makes the redaction boundary everyone's problem instead
of the normalizer's.

**A separate observation API: `SwarmExecutor#observe(command) -> Observation`, distinct
from `execute`.** Cleaner in the abstract. Rejected: it puts two return types on one
boundary, and the boundary is the thing `ADR-0005` promises to keep swappable. It also
splits the outcome vocabulary — a not-found observation has no `outcome` to report — and
`retry_after_observing` (`swarm_executor.rb:76-95`) already composes observation with
execution through `ExecutionResult`.

**Let the reconciler read the Engine directly for inspects.** Rejected without weighing:
`docs/AGENT_RULES.md` "Architecture Invariants" and Annex C §8 make the executor the only
privileged Docker boundary, and AF-01/AF-02 enforce it.

**Skip the inspect and trust `network.swarm_network_id` from PostgreSQL.** Rejected:
Actual State is observed, never assumed (doc 07 §11.3 step 3). It would make AC3 and AC11
untestable and turn `READY` into a stored boolean.

**One typed class per kind (`NetworkObservation`, `ServiceObservation`, `NodeObservation`).**
Rejected as premature: three kinds, one consumer each, and a shared `labels` predicate. A
single `Data` with `kind` plus an allowlisted `attributes` map is the smaller thing that
works, and splitting it later is mechanical.

## Consequences

**What changes now, inside `M01-17`'s boundary:**

- `app/executors/execution_result.rb` — the `observed` field and the two factory signatures.
- `app/executors/swarm_executor.rb` — a private normalizer per kind; `do_inspect_*` and the
  two adoption `NOOP`s return observations; label-based addressing replaces path
  interpolation for owned resources; `find_by_label`'s prefix sniffing goes.
- `lib/opanel/runtime_observation.rb` — new.
- `lib/opanel/ownership.rb` — `managed_by_platform?` and the anomaly log take an observation.
- `lib/opanel/network_diff.rb` — reads `actual.name` / `actual.labels`.
- `app/reconcilers/network_reconciler.rb` — reads `result.observed`; passes
  `environment.external_id` as `resource_id`; and `network_reconciler.rb:195`'s
  `result.ids&.first` becomes `result.runtime_resource_ids.first` — `ids` is a method
  `ExecutionResult` does not have, so that line raises today.
- `spec/contracts/executor_contract_spec.rb:26-27` — `RESULT_FIELDS` gains `observed`, plus
  the new assertions: an `APPLIED` inspect always carries one; a `FAILED`/`RETRYABLE`/
  `CONFLICT` result never does; `safe_metadata` still carries no body; the forensic log line
  of `record` still has its fixed key set and `observed` is not among them.
- `spec/unit/network_reconciler_spec.rb:28,51` — the `network_data: nil` stubs are replaced
  by real `RuntimeObservation` values. They are being corrected, not weakened: they were
  green against a key no executor writes.
- `spec/unit/swarm_executor_spec.rb`, `spec/integration/swarm_ownership_labels_spec.rb` —
  ownership fixtures become observations.

**What a Story inherits, and is not licensed to do here:**

- `app/commands/observe_cluster_nodes.rb:47` reads `list_result.safe_metadata[:ids]`, which
  `do_list_nodes` (`swarm_executor.rb:185-192`) never writes — it writes
  `runtime_resource_ids`. So `node_ids` is always empty and the observation loop never runs:
  the same missing contract, a second time. Fixing that line belongs to whichever Story
  next touches node observation, with a lab assertion; this ADR only names it.
  `process_node_inspection` keeps working against `safe_metadata` scalars until then, and
  should move to `observed.attributes` when it is touched.
- `network_reconciler.rb:112,176` build the command id as
  `Opanel::Identifier.external(:operation, SecureRandom.uuid)` — a UUID inside an external
  id. `ExecutorCommand#id` is never validated, so it changes no assertion; it is an ADR-0002
  conformance defect and is fixed as one, not decided here.
- `docs/architecture/07-internal-control-plane.md` §20.2 now understates the contract by one
  field. The document is **not** edited; the divergence is recorded in
  `docs/decisions/pending-documentation-updates.md`, per `AGENT_RULES.md` "Documentation".

**Cost and blast radius.** Two production callers construct `ExecutorCommand` today
(`network_reconciler.rb`, `observe_cluster_nodes.rb`), which is why this is decided now
rather than after `M01-18`: the Service Reconciler, `M01-19`…`M01-23` and every future
reconciler read Actual State through this field, and each one added before the contract
exists is another caller to migrate. `observed` defaults to `nil`, so no existing call site
breaks on construction; the migration is per-reader, which is the expand half of
expand-contract. There is no contract phase to schedule: `safe_metadata` is not being
narrowed, only held to the meaning it already documents.

**Affected Stories.** `M01-17` leaves `BLOCKED` and resumes on this record. `M01-18`
(Service Reconciler) inherits the contract and is the first Story to add a `service` kind
to the normalizer under real pressure. `M01-19` through `M01-23` inherit it unchanged.
`M02-EXEC-SPLIT` (`ADR-0005`) inherits the JSON-serializability constraint stated in §2.

## Review

Written by the `adr-author` agent in a fresh read-only context, on an arbiter
`BLOCK` with `Blocks-On: ADR`. No human read it before the run continued; it
reaches a human in the Milestone's Pull Request, which is where every autonomous
decision in this project is reviewed.
