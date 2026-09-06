import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import type { Reporter, TestCase, TestResult } from '@playwright/test/reporter';

/**
 * Separates a retry caused by infrastructure from a retry caused by an assertion.
 *
 * Playwright retries a whole test and reports both the same way. That matters
 * here: a test that failed because the server had not booted is an environment
 * problem, and a test that failed an expectation is a defect or a flake. Counting
 * them together produces a flaky-rate number nobody can act on (Annex D §20.1),
 * and hides the case where a suite is only green because it kept trying.
 *
 * Writes tmp/test-results/e2e-retries.json for the CI report.
 */

export type RetryKind = 'assertion' | 'infrastructure' | 'unknown';

interface RetryRecord {
  test: string;
  file: string;
  attempt: number;
  kind: RetryKind;
  reason: string;
}

const INFRASTRUCTURE_SIGNALS = [
  'net::ERR_CONNECTION_REFUSED',
  'net::ERR_EMPTY_RESPONSE',
  'ECONNREFUSED',
  'ECONNRESET',
  'Timed out waiting',
  'browserType.launch',
  'Target page, context or browser has been closed',
  'webServer',
];

const ASSERTION_SIGNALS = ['expect(', 'Expected:', 'toBeVisible', 'toHaveText', 'AssertionError'];

export function classify(result: Pick<TestResult, 'status' | 'error' | 'errors'>): {
  kind: RetryKind;
  reason: string;
} {
  const text = [
    result.error?.message,
    result.error?.stack,
    result.errors.map((e) => e.message).join('\n'),
  ]
    .filter(Boolean)
    .join('\n');

  if (result.status === 'timedOut' && !ASSERTION_SIGNALS.some((signal) => text.includes(signal))) {
    return { kind: 'infrastructure', reason: 'test timed out with no failed expectation' };
  }

  const infrastructure = INFRASTRUCTURE_SIGNALS.find((signal) => text.includes(signal));
  if (infrastructure) {
    return { kind: 'infrastructure', reason: infrastructure };
  }

  const assertion = ASSERTION_SIGNALS.find((signal) => text.includes(signal));
  if (assertion) {
    return { kind: 'assertion', reason: text.split('\n')[0]?.slice(0, 200) ?? assertion };
  }

  return { kind: 'unknown', reason: text.split('\n')[0]?.slice(0, 200) ?? 'no error recorded' };
}

class ClassifiedReporter implements Reporter {
  private retries: RetryRecord[] = [];

  onTestEnd(test: TestCase, result: TestResult) {
    if (result.retry === 0 && result.status !== 'failed' && result.status !== 'timedOut') return;
    if (result.status === 'passed' && result.retry === 0) return;

    const { kind, reason } = classify(result);

    this.retries.push({
      test: test.titlePath().slice(1).join(' › '),
      file: test.location.file,
      attempt: result.retry + 1,
      kind,
      reason,
    });
  }

  onEnd() {
    const path = 'tmp/test-results/e2e-retries.json';
    mkdirSync(dirname(path), { recursive: true });

    const summary = {
      total: this.retries.length,
      assertion: this.retries.filter((r) => r.kind === 'assertion').length,
      infrastructure: this.retries.filter((r) => r.kind === 'infrastructure').length,
      unknown: this.retries.filter((r) => r.kind === 'unknown').length,
      retries: this.retries,
    };

    writeFileSync(path, JSON.stringify(summary, null, 2));

    if (summary.total > 0) {
      // eslint-disable-next-line no-console -- M00-08: the reporter's job is to print
      console.log(
        `\ne2e retries: ${summary.assertion} assertion, ${summary.infrastructure} infrastructure, ` +
          `${summary.unknown} unclassified — see ${path}`,
      );
    }
  }
}

export default ClassifiedReporter;
