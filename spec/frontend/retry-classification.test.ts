import { describe, it, expect } from 'vitest';

import { classify } from '../../e2e/support/classified-reporter';

type Result = Parameters<typeof classify>[0];

function result(overrides: Partial<Result>): Result {
  return { status: 'failed', errors: [], ...overrides } as Result;
}

/**
 * A flaky suite is a defect with an owner and a deadline (Annex D §20.1). Acting
 * on that needs the report to say *why* a test was retried: an environment that
 * was not ready is a different problem from an assertion that failed, and
 * counting them together produces a flaky rate nobody can use.
 */
describe('e2e retry classification', () => {
  it('classifies a refused connection as infrastructure', () => {
    const { kind, reason } = classify(
      result({ error: { message: 'net::ERR_CONNECTION_REFUSED at http://127.0.0.1:3999/' } }),
    );

    expect(kind).toBe('infrastructure');
    expect(reason).toContain('ERR_CONNECTION_REFUSED');
  });

  it('classifies a web server that never came up as infrastructure', () => {
    expect(classify(result({ error: { message: 'Error: webServer did not start' } })).kind).toBe(
      'infrastructure',
    );
  });

  it('classifies a timeout with no failed expectation as infrastructure', () => {
    expect(
      classify(
        result({ status: 'timedOut', error: { message: 'Test timeout of 30000ms exceeded' } }),
      ).kind,
    ).toBe('infrastructure');
  });

  it('classifies a failed expectation as an assertion', () => {
    const { kind, reason } = classify(
      result({ error: { message: 'expect(received).toBeVisible()\nExpected: visible' } }),
    );

    expect(kind).toBe('assertion');
    expect(reason).toContain('expect(');
  });

  it('classifies a timeout caused by an expectation as an assertion, not as flakiness', () => {
    expect(
      classify(
        result({
          status: 'timedOut',
          error: { message: 'Timed out 10000ms waiting for expect(locator).toBeVisible()' },
        }),
      ).kind,
    ).toBe('assertion');
  });

  it('refuses to guess when the failure says nothing recognisable', () => {
    expect(classify(result({ error: { message: 'something nobody predicted' } })).kind).toBe(
      'unknown',
    );
  });
});
