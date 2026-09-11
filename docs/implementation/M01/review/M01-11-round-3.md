# M01-11 — independent review (round 3)

**Base commit**: `21a5852`
**Reviewer**: independent
**Status**: after fixes for the round-2 Critical (AC9) and the order-dependent pagination spec

## AC9 (Cluster DEGRADED) — Fixed and Verified Correct

**Implementation** (`app/commands/create_environment.rb`):
- AC4 check first: `return failure("NOT_FOUND", CLUSTER_NOT_FOUND) if cluster.nil?`
- AC9 check after: `return failure("VALIDATION_ERROR", CLUSTER_NOT_READY, field: "cluster") unless cluster.ready?`

**Critical ordering verified**: AC4 (nil check) executes **before** AC9 (readiness check). A
cluster belonging to another team is nil after `TenantScope.for(actor, Cluster).find_by_external_id()`,
triggering NOT_FOUND. Only if cluster is not nil does `cluster.ready?` evaluate.

**Leak risk assessment**: No tenancy leak. A foreign DEGRADED cluster returns `NOT_FOUND` (same as
a missing cluster), not a `VALIDATION_ERROR` readiness message that would reveal its existence and
state. AC4 is preserved.

**Predicate verified**: `Cluster#ready?` (`app/models/cluster.rb:89`) returns `status == READY`
against the correct constant.

**Test coverage**: DEGRADED rejection (VALIDATION_ERROR, message matching "not ready") and READY
acceptance, both in `spec/integration/environment_constraints_spec.rb`; the cross-team spec still
passes.

**Finding**: AC9 correctly implemented. No tenancy leak. Readiness validation reachable and
properly ordered.

## Pagination Index Test — Fixed and Not Weakened

**File**: `spec/integration/environment_constraints_spec.rb`

**Method of fix**: 3 additional projects with 5 environments each (15 rows elsewhere), 3 rows in
the target project, then `ANALYZE environments`, then EXPLAIN asserting the plan contains
`index_environments_on_project_id_and_id` by name.

**Why this fixes the flakiness**: with 18 rows, walking the primary key to read and discard 15
rows from other projects is expensive; the composite index becomes cheaper. After ANALYZE the
planner has accurate statistics and chooses it. The test does not accept "any index" — it checks
the exact index name.

**Assertion strength**: NOT weakened. No skip, pending, retry or seed pin. Passes across seeds
55514 (originally failing), 12345 and 99999.

**Finding**: corrected. The composite index is genuinely the better plan.

## Acceptance Criteria — All Implemented

| AC | Evidence | Status |
|---|----------|--------|
| AC1 | CreateEnvironment with explicit cluster/type selection | Implemented, tested |
| AC2 | UNIQUE(projectId, slug) WHERE deletedAt IS NULL | Partial unique index; negative test |
| AC3 | Environment refs Cluster; Project not hierarchically dependent | environments.cluster_id FK, no cluster_id on projects |
| AC4 | Cross-team Cluster access denied indistinguishably | TenantScope + nil-check-first ordering; tested |
| AC5 | autoPromoteSecrets false default in PRODUCTION | CHECK `environments_production_no_auto_promote`; tested |
| AC6 | desiredRevision/appliedRevision increment properly | Starts at 1; increments on slug change only |
| AC7 | Status derived, no stored boolean | Column only; no health boolean; tested |
| AC8 | PRODUCTION badge persistent in UI | EnvironmentBadge with data-testid; frontend test |
| AC9 | DEGRADED produces block with explicit message | cluster.ready? check; DEGRADED rejection + READY acceptance |
| AC10 | Mutations audit and pass Policy with cross-team negative | AuditTrail.record in both commands; EnvironmentPolicy; cross-team test |
| AC11 | Archiving Project with active Environment blocked | ArchiveProject.blocking_reason checks environments.kept.exists? |

## Architecture Invariants — Upheld

- Tenant scoping: `accessible_to` joins through Team membership; `TenantScope.for()` applied
- Authorization: EnvironmentPolicy instantiated explicitly in both Commands
- One-transaction writes: transaction wraps create + AuditTrail.record
- No network calls in transaction: database operations only
- Secrets: no plaintext; audit sanitizer allowlists safe fields only

## Security — No Findings

Cross-team attempts return NOT_FOUND (indistinguishable from missing). Server-side Policy checks.
Audit recorded atomically. Slug format, name length and cluster status validated. No stack traces
or internal detail in responses.

## Test Execution — PASSING

Ruby suite (lead-executed evidence): 9 files, 138 examples, 0 failures, seeds 55514 (originally
failing), 12345, 99999. Frontend: `spec/frontend/environments-page.test.tsx` 4 passed.

**Gate status**: the local gate could NOT be run — the Docker daemon on this machine is
unresponsive and the gate hangs on an unbounded `docker info` in `spec/unit/preflight_spec.rb`.
Recorded as `BLOCKED_EXTERNAL_DEPENDENCY` in
`docs/implementation/M01/evidence/M01-11-gate-blocked.md`. This is machine state, not a code
defect, but it leaves the gate's own checks — lint, typecheck, migration validation, fitness
functions including AF-07 — **unverified** for this Story.

## Boundary — No Violations

All touched files remain within the declared M01-11 boundary.

## Summary

Both fixes are correct. All 11 acceptance criteria implemented. Tests comprehensive and passing.
No Critical or High findings. Gate blocked by external dependency, not by a code defect.

COUNTS 0 0 0 0
