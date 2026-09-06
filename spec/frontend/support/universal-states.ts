/**
 * The universal UI states of doc 10 §25, expressed once as a contract both the
 * component tests and the browser journeys assert against.
 *
 * Every one of these is a state the interface must be able to *show*. A page that
 * can only render its happy path is incomplete, and from M00-08 a UI Story without
 * coverage of its error, empty and forbidden states is a review finding — not
 * future polish.
 *
 * The signature of each state is a role, an accessible name or a stable test id.
 * Never a CSS class: that is a styling decision, and lint rejects it (Annex D
 * §11.1).
 */
export type UniversalState =
  | 'loading'
  | 'empty'
  | 'no-permission'
  | 'offline'
  | 'stale'
  | 'operation-running'
  | 'partial-failure'
  | 'deleted';

export interface StateContract {
  /** Stable test id a page sets on the region that carries this state. */
  testId: string;
  /** ARIA role the region must expose, when the state has one. */
  role?: string;
  /** Why the state exists — quoted in a failure message so it reads as a rule. */
  rule: string;
}

export const UNIVERSAL_STATES: Record<UniversalState, StateContract> = {
  loading: {
    testId: 'state-loading',
    role: 'status',
    rule: 'Skeleton of the structure, not a full-page spinner outside bootstrap.',
  },
  empty: {
    testId: 'state-empty',
    rule: 'Explain the value and offer a contextual call to action.',
  },
  'no-permission': {
    testId: 'state-no-permission',
    role: 'alert',
    rule: 'Explain the restriction without leaking the data behind it.',
  },
  offline: {
    testId: 'state-offline',
    role: 'alert',
    rule: 'Preserve the last reading with its timestamp; block mutations.',
  },
  stale: {
    testId: 'state-stale',
    rule: 'Show "last observed …". Never claim Healthy without a recent observation.',
  },
  'operation-running': {
    testId: 'state-operation-running',
    rule: 'The primary action is disabled or replaced while the operation runs.',
  },
  'partial-failure': {
    testId: 'state-partial-failure',
    role: 'alert',
    rule: 'Show the parts: "7/8 replicas healthy", never a bare "failed".',
  },
  deleted: {
    testId: 'state-deleted',
    rule: 'Read-only during the retention window.',
  },
};

export function stateTestId(state: UniversalState): string {
  return UNIVERSAL_STATES[state].testId;
}

export function stateRule(state: UniversalState): string {
  return UNIVERSAL_STATES[state].rule;
}
