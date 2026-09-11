# Review — M01-10 (Round 2)

**Story:** M01-10 — Node registration and observation
**Reviewer:** independent
**Date:** 2026-09-10

## Acceptance Criteria Coverage

| # | Criterion | Test Evidence | Status |
|---|-----------|---|--------|
| 1 | Nodes appear as Node records | `spec/integration/swarm_nodes_lab_spec.rb:58` | Satisfied |
| 2 | swarm_node_id UNIQUE per cluster | `db/migrate/20260909121000_create_nodes.rb` | Satisfied |
| 3 | NodeObservation separate from Node | Schema: two tables, two models | Satisfied |
| 4 | Status derived from observation | `observation_stale?` reads `NodeObservation.observed_at` | Satisfied |
| 5 | Staleness marked in UI | Frontend badge uses `node.stale?` predicate | Satisfied |
| 6 | Docker failure preserves observation | `spec/unit/observe_cluster_nodes_spec.rb:154` | Satisfied |
| 7 | Disappeared node → DOWN | `spec/integration/node_observation_spec.rb:1734–1799` | **FIXED** |
| 8 | Idempotent via concurrent calls | `find_or_create_by(swarm_node_id:)` with database unique constraint | Satisfied |
| 9 | Cross-team access denied | `spec/policies/node_cross_team_spec.rb:16` | Satisfied |
| 10 | No secrets in logs/responses | `spec/security/node_observation_redaction_spec.rb` | Satisfied |
| 11 | Fitness function blocks multi-node in-process | Arbitrated to DEBT (ADR-0007); recorded in `DECISIONS.md` | Deferred |

---

## Round-1 Finding Resolution

**F-1 (Critical) — `mark_disappeared_nodes_as_down` stub — CLOSED**

- **Implementation:** Lines 149–175 (`app/commands/observe_cluster_nodes.rb`) now contain 27 lines of working code:
  - Queries for nodes absent from current Swarm list
  - Updates them to `Node::DOWN`
  - Creates immutable `NodeObservation` records
  - Does NOT delete nodes

- **Test:** Lines 1734–1799 (`spec/integration/node_observation_spec.rb`) now calls `ObserveClusterNodes.call()` with mocked executor:
  - Creates two nodes
  - First observation: both present
  - Second observation: only node1 present; node2 disappeared
  - Asserts `node2.status == Node::DOWN` (line 1792)
  - Asserts `node2.persisted? == true` (line 1793) — not deleted
  - Asserts observation history includes both READY and DOWN (line 1798)

This test would fail if the method were still a stub. **Resolved.**

---

**F-4 (Medium) — Staleness derivation — CLOSED**

- `Node#observation_stale?` (lines 495–500, `app/models/node.rb`) now reads:
  ```ruby
  now - latest.observed_at > FRESH_OBSERVATION_SECONDS
  ```
  Staleness is derived from the authoritative `NodeObservation.observed_at`, not the denormalized `Node.last_seen_at`. **Resolved.**

---

**F-5 (Low) — Misleading comment — CLOSED**

- Lines 145–148 (`app/commands/observe_cluster_nodes.rb`) now accurately describe the implementation, no longer aspirational. **Resolved.**

---

**F-3 (High) — Boundary violation — CLOSED**

- Live `docs/implementation/M01/boundaries.yml` verification:
  - `grep -c "node_cross_team_spec"` = 1 (exactly one occurrence)
  - Located at line 612, under M01-10 entry
  - M01-08 entry (lines 410–472) does not include it

The confusion arose from reading the round-1 review document (quoted in the diff) rather than the live file. The boundary is correctly declared under M01-10 only. **Resolved.**

---

**AC11 (Fitness function) — Properly arbitrated to DEBT**

- Verdict recorded in `DECISIONS.md` (2026-09-10 UTC)
- Deferral path accepted by `acceptance_mapping.rb` (ADR-0005, ADR-0007)
- AC11 remains unticked, properly accounted for. Does not block DONE under this arbitration.

---

## New Finding

**Broad `rescue StandardError` masking programming errors — MEDIUM**

**Location:**
- `app/commands/observe_cluster_nodes.rb` lines 72–76
- `app/jobs/observe_cluster_nodes_job.rb` lines 381–385

**Issue:** Any `StandardError` (including `NoMethodError`, `ArgumentError`, etc.) is caught and converted to a domain result code "OBSERVATION_FAILED". This makes programming bugs indistinguishable from Docker API failures.

**Example:** A bug in `process_node_inspection` (e.g., accessing nil attribute) will be logged as a cluster observation failure but will not propagate as an exception, visible only in logs.

**Mitigation:** Consider catching only Docker-specific exceptions or letting programming errors propagate. This is a design choice trading debuggability for operational robustness.

**Severity:** MEDIUM (maintainability; does not affect correctness or security).

---

## Architecture Invariants

- **Desired vs Actual State:** Respected ✓
- **Reconciliation:** Observes Docker, persists observations, denormalizes ✓
- **Idempotency:** `find_or_create_by` on unique constraint ✓
- **Docker socket isolation:** SwarmExecutor only ✓
- **Secrets:** No plaintext in logs/responses ✓
- **Transactions:** No network calls inside ✓

---

## Security

- Cross-team scope enforced ✓
- Private addresses restricted to team members ✓
- No credentials in payloads ✓

---

## Observability

- Correlation IDs: `Current.request_id` ✓
- Cluster degradation cause logged ✓
- Per-node events specific ✓
- Team/cluster IDs in logs ✓

---

## Dependencies

None new. ✓

---

## Summary

| Category | Count | Status |
|---|---|---|
| Critical | 0 | All fixed |
| High | 0 | All fixed |
| Medium | 1 | Broad rescue |
| Low | 0 | All fixed |

Story ready for DONE. One Medium finding on error handling; does not block completion.

COUNTS 0 0 1 0
