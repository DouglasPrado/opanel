---
title: "Flaky tests"
type: "engineering-convention"
---

# Flaky tests

**A flaky test is a defect.** Not noise, not an environment quirk, not something
to re-run. It is usually a real race, a real ordering dependency or a real
timeout, and the intermittency is the symptom rather than the problem.

It is never resolved by retrying until green. A suite that passes on the third
attempt has stopped telling anyone anything, and the bug it found is still there
(Annex D §20.1).

## What to do instead

1. **Reproduce it.** The suite runs in random order and reports its seed:
   `bin/test --seed <seed>` replays the exact ordering. Most "flaky" tests are
   order-dependent and stop being intermittent the moment the seed is fixed.
2. **Look for the real cause.** In this repository the usual ones are a missing
   barrier in a concurrency test, a wall-clock dependency that should use
   `travel_to`, a leaked row from a non-transactional example, and a parallel
   worker colliding on a name that should have come from `unique_namespace`.
3. **If it cannot be fixed now, quarantine it — with an owner and a deadline.**

```ruby
it "converges after a partial failure", quarantine: {
  owner: "douglas",
  until: "2026-10-01",
  reason: "races with the recovery sweep; see M01-15"
} do
```

The example is skipped until the deadline. **After the deadline it runs again**,
and if it is still flaky the suite goes red. A quarantine cannot decay into a
permanent way of not looking at something, and one without an owner, a deadline
and a reason is rejected outright.

## What may never be quarantined

An intermittent failure in a **security**, **restore** or **concurrency** test
blocks release until it is understood. Those are the tests whose intermittency is
most likely to *be* the bug: a race that leaks a secret one time in fifty is still
a leak. `spec/security` examples are refused a quarantine tag by the harness.

## Retries

- `bin/test` does not retry. A failure is a failure.
- `bin/test:e2e` allows Playwright one retry, and the report separates an
  infrastructure retry from an assertion retry
  (`tmp/test-results/e2e-retries.json`). The distinction is the point: a server
  that had not booted is an environment problem, and a failed expectation is a
  defect or a flake. Counting them together produces a number nobody can act on.
- CI publishes the retry counts per run. A test appearing there repeatedly is
  quarantined with an owner, not ignored.
