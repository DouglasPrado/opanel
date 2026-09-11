# Review — M01-18 — round 3

> **Provenance note, written by the lead, not by the reviewer.** The `reviewer`
> agent holds `Read`, `Grep` and `Glob` and no `Write`; its reply is persisted
> here verbatim by the lead, unaltered. `COUNTS 0 1 2 0` is recorded through
> `tasks.sh review` exactly as returned. The lead does not adjust a reviewer's
> counts and does not reconcile them with the prose.

---

Based on my review of the test, implementation, and report, I can now provide my findings.

## Findings

### Acceptance Criteria / F-1 Status

**Question 1: Which discriminator carries the result in the restored example?**

In the test scenario (`service_blocked_lab_spec.rb:150-177`), the old Rejected task is excluded by **both** the Version.Index-per-Slot filter and the `superseded_spec?` filter acting in sequence:
- **Version.Index filter** (lines 324-335): Groups tasks by Slot, keeps only the highest Version.Index. The new task created after the image fix gets a higher index than the old Rejected task.
- **superseded_spec? filter** (lines 342-346): Old task's image (`sha256:0000...`) does not match desired image (`lab_digest`), so it's rejected.

The test does not isolate which filter does the critical work. Both would exclude the task. The story intends the Version.Index filter to be primary (per the comment at line 118-127), but the test passes because the new task has the correct image, making `superseded_spec?` do the work.

**Question 2: Is the Version.Index-per-Slot rule sound on its own terms?**

The comment at lines 306-311 assumes Docker "assigns a higher Version.Index to replacement tasks in the same slot." This is reasonable for new replacements, but the arbiter's concern is valid: Version.Index is described as incrementing on every status transition. A long-lived task with many state changes could theoretically outrank a newer replacement that has fewer transitions. The test does not cover a scenario where this would occur (e.g., a replacement created immediately after the old task failed). **This remains untested.**

**Question 3: Is `superseded_spec?` safe?**

Returns false if either image is nil (line 350). At the call sites in the reconciler, `desired_image` should never be nil because `diff` would return BLOCKED before reaching task filtering. However, the defensive nil checks are appropriate. Line 1 at line 349 correctly uses `dig()` for safe navigation. **Appears safe.**

**Question 4: Could the example pass vacuously?**

- Line 160 sets `desired_revision: original_desired_revision + 1` manually, which is artificial but necessary to trigger reconciliation.
- The `wait_for` loop (lines 163-168) actively waits for SUCCESS; without it, the test would not wait for convergence.
- The final `expect(result.result).to eq(ReconciliationRun::SUCCESS)` requires real convergence.
- The `expect(current_report).to include("Rejected")` assertion (line 176) proves the old task remains in Docker's history.

**Not vacuous.** The test exercises the full reconciliation path and validates the filter works.

### F-1 Resolution

**F-1 is closed by functional evidence**, not implementation proof. The test demonstrates that a Service blocked by an unresolvable image digest can recover when the digest is fixed, and the old failed task (still in history) does not cause re-blocking. This proves the filtering works in this scenario.

However: the test does not isolate whether the Version.Index logic alone is sufficient and correct. It passes because `superseded_spec?` also filters the task. If the Version.Index rule has an edge case (a task with many transitions outranking its replacement), the test would not catch it. **The test proves the fix works, but not that the implementation is robust.**

### Unperformed Items (Round 1)

Both are now performed and tested:

1. **Operation scoping by team** (line 84-90, `app/jobs/reconcile_services_job.rb`): Operations are queried `where(team_id: operation.team_id)`. ✓
2. **Cross-team negative on reconcile** (line 144-164, `spec/policies/service_policy_spec.rb`): Test at line 144 verifies cross-team users cannot see the reconciliation run; line 160-164 asserts it records under the Service's Team. ✓

Both are cited in the report (lines 29-30, 193) accurately.

### Report Honesty

The report (line 126-156) accurately records that the recovery example failed, was deleted, and was restored. Line 148 claims "The filter... correctly prevents historical task errors from re-blocking" — which is true for this scenario but does not address whether the Version.Index logic is sound on its own. This is acceptable given the test passes, but the report could have been more explicit about what the test isolates and what it does not.

### Boundary

No violations detected. All modified files are within the declared M01-18 boundary (lines 1133-1223).

---

**Summary:** F-1 is functionally fixed (Service recovers from BLOCKED), and the test proves the filter works. However, the test does not validate the robustness of the Version.Index-per-Slot logic in edge cases. The implementation appears correct for normal operation, but edge-case validation of the Version.Index assumption is missing. This is acceptable as a passing story if treated as technical debt (the filter works in practice, but the justification is incomplete).

COUNTS 0 1 2 0
