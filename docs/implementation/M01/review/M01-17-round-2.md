Based on my review of the Story M01-17 round 2, I've found several critical issues:

## CRITICAL FINDINGS

**1. False attribution of test failures — acceptance criteria mapped to failing tests**

The builder's report claims the 5 lab test failures are "Docker VALIDATION_ERROR (HTTP 400) when POST `/networks/create`, despite identical curl requests succeeding (HTTP 201)."  However, the diff itself includes diagnostic evidence (in the BLOCKERS.md section added to the report) that proves:

- Network names generated: `net_<prj_ULID>_<env_ULID>` = **65 characters**
- Docker limit: 63 characters  
- Curl with the full 65-char name: HTTP 400, error "name must be 63 characters or fewer"
- Curl with the same name truncated to 63 chars: HTTP 201

The requests are NOT "identical"—the successful one uses a truncated name. The root cause is code at `lib/opanel/ownership.rb:90-104`, which the arbitration explicitly forbade this round from editing (Decision at DECISIONS.md:317: "Explicitly **not** in this round"). Therefore:

- AC1, AC2, AC3, AC4, AC5, AC6, AC8 all depend on network creation succeeding
- All 5 lab test failures are caused by this name-length defect, not Docker-side issues
- None of these 6 ACs can be verified as passing when the tests fail due to an unfixed code defect

**File/Line evidence:** `/Users/douglasprado/www/opanel/docs/implementation/M01/reports/M01-17.md:140-157` (builder's claim); `/Users/douglasprado/www/opanel/docs/implementation/M01/BLOCKERS.md:489-548` (diagnostic showing the actual cause).

**2. Acceptance criteria reported satisfied despite test failures**

The report's AC mapping table (lines 49-60) marks AC1, AC2, AC3, AC4, AC5, AC6, AC8 as passing or relying on unit tests, but the lab tests that prove the critical AC1 (network creation) all fail. An acceptance criterion is satisfied only by a passing test, per Annex D §1.

## HIGH FINDINGS

**3. Boundary scope — mandatory spec migrations not actually completed**

The arbitration authorized changes to `lib/opanel/ownership.rb` for the `managed_by_platform?` signature update (ADR-0009 §4). However, the diff shows changes only to that method and `log_anomaly`, leaving `technical_name_for` (lines 90-104) untouched—the method that's the root cause of all 5 lab failures. While the round correctly updated the ownership predicate, it left the defect that blocks all downstream Stories (M01-18 through M01-23) because the Service reconciler will generate 96-char names that also exceed Docker limits.

**File/Line evidence:** `/Users/douglasprado/www/opanel/tmp/review/M01-17.diff:2701-2790` shows changes to `managed_by_platform?` and `log_anomaly` only, not `technical_name_for`.

**4. Spec migrations claim not verified against actual test execution**

The report states "21 passing, 5 failing" but the builder claims the failing tests are all Docker-side and unrelated to the code changes. If that were true, the 21 passing tests (unit and ownership predicate migrations) would confirm the migrations are correct. However, with 5 lab tests red and 6 ACs dependent on them, the story's own DoD requirement ("12 Acceptance Criteria satisfeitos contra Swarm real", line 90 of the story) is not met.

---

## SUMMARY

The diff touches `lib/opanel/ownership.rb` as required by ADR-0009, but evidence in the diff itself (BLOCKERS.md section) proves the 5 lab test failures are not Docker-side issues but code defects in the same file's `technical_name_for` method—which the arbiter explicitly forbade this round from editing. This means:

- No AC requiring network creation can be verified as passing
- The root cause remains unfixed and blocks M01-18 onwards
- The builder's misclassification of the failures masks the scope of what's unresolved

COUNTS 1 1 0 0
