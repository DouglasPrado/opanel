import { execFileSync } from 'node:child_process';

/**
 * Redacts the failure artifacts before anyone can archive them.
 *
 * A trace, a screenshot and a video record whatever was on screen and on the
 * wire. That is exactly why they are useful, and exactly why they cannot be
 * uploaded unexamined: a token in a header or a secret in a field would be
 * published to CI storage and to anyone with the artifact link (Annex C §17.1).
 *
 * `bin/redact-artifacts` masks what it can and deletes what it cannot, and exits
 * non-zero when it had to delete — so a leak fails the run instead of shipping.
 */
export default function globalTeardown() {
  // Only the recordings: the trace, screenshot, video and error-context files
  // Playwright wrote, plus the JSON reports. The HTML report is generated from
  // these, so cleaning the source cleans the report — and scanning Playwright's
  // own bundled viewer would only produce false positives in minified code.
  execFileSync(
    'bin/redact-artifacts',
    [
      'tmp/test-results/e2e',
      'tmp/test-results/e2e-report.json',
      'tmp/test-results/e2e-retries.json',
    ],
    { stdio: 'inherit' },
  );
}
