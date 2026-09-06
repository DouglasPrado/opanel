import type { ReactNode } from 'react';
import { render, screen } from '@testing-library/react';
import { expect } from 'vitest';

import { UNIVERSAL_STATES, type UniversalState } from './universal-states';

/**
 * Renders a subtree and asserts it presents one of the universal states of
 * doc 10 §25 by its contract — the test id and, when the state has one, the ARIA
 * role. The failure message quotes the rule so a reader learns why the state
 * exists, not just that an assertion failed.
 */
export function expectStateRendered(state: UniversalState, ui: ReactNode) {
  const contract = UNIVERSAL_STATES[state];

  render(<div data-testid={contract.testId}>{ui}</div>);

  const region = screen.getByTestId(contract.testId);
  expect(region, `the "${state}" state did not render. Rule: ${contract.rule}`).toBeInTheDocument();

  if (contract.role) {
    expect(
      region.querySelector(`[role="${contract.role}"]`) ??
        region.closest(`[role="${contract.role}"]`),
      `the "${state}" state must expose role="${contract.role}". Rule: ${contract.rule}`,
    ).not.toBeNull();
  }

  return region;
}
