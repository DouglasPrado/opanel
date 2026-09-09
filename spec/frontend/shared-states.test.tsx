import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import {
  EmptyState,
  ErrorState,
  LoadingState,
  NoPermissionState,
  OfflineState,
  StaleState,
} from '@/components/shared/states';
import { Button } from '@/components/ui/button';
import { UNIVERSAL_STATES } from './support/universal-states';

/**
 * AC3: the universal states exist as reusable components, covered by test.
 *
 * M00-08 proved these states can be assembled from the imported library. What is
 * asserted here is different and is what AC3 asks for: that a page gets the
 * contract — the test id the journeys look for, the ARIA role a screen reader
 * needs — by *composing* rather than by remembering. Every assertion below is
 * against `UNIVERSAL_STATES`, the same contract the E2E journeys use, so the two
 * cannot drift.
 */
describe('the universal state components', () => {
  it('renders loading with the status role the contract requires', () => {
    render(<LoadingState label="Loading services" />);

    const region = screen.getByTestId(UNIVERSAL_STATES.loading.testId);
    expect(region).toHaveAttribute('role', UNIVERSAL_STATES.loading.role);
    expect(region).toHaveAccessibleName('Loading services');
  });

  it('renders empty with what it is for and the action that fills it', () => {
    render(
      <EmptyState
        title="No services yet"
        description="Deploy an image to see it running here."
        action={<Button size="sm">Deploy a service</Button>}
      />,
    );

    expect(screen.getByTestId(UNIVERSAL_STATES.empty.testId)).toBeInTheDocument();
    expect(screen.getByText('No services yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Deploy a service' })).toBeInTheDocument();
  });

  it('renders no-permission as an alert, explaining without naming the resource', () => {
    render(<NoPermissionState description="You need the ADMIN role to change members." />);

    const region = screen.getByTestId(UNIVERSAL_STATES['no-permission'].testId);
    expect(region.querySelector('[role="alert"]')).toBeInTheDocument();
    expect(screen.getByText(/ADMIN role/)).toBeInTheDocument();
  });

  describe('the error state', () => {
    it('shows the request id so support can find the same request', () => {
      render(<ErrorState description="The service could not be reached." requestId="req_abc123" />);

      expect(screen.getByTestId('state-error-request-id')).toHaveTextContent('req_abc123');
    });

    /**
     * AC4, with the detail actually planted.
     *
     * The first version of this example passed a clean string and then asserted
     * the clean string contained no stack trace — true, and worthless. Review
     * proved it by rendering a real exception message and watching it print
     * verbatim with the suite green. Every case here feeds the component exactly
     * what must never reach a screen.
     */
    it.each([
      ['a Rails exception with a path', "ActiveRecord::RecordNotFound: Couldn't find Team (/app/controllers/panel_controller.rb:29)"],
      ['a SQL statement', 'PG::Error: SELECT * FROM teams WHERE id = $1'],
      ['a stack frame', "undefined method `slug' for nil:NilClass\n  at /usr/local/lib/app.rb:12"],
      ['a bare exception class', 'NoMethodError'],
    ])('refuses %s rather than rendering it', (_name, planted) => {
      render(<ErrorState description={planted} requestId="req_abc123" />);

      const body = screen.getByTestId('state-error').textContent ?? '';

      expect(body).not.toContain(planted);
      expect(body).toMatch(/something went wrong/i);
      // The request id survives — it is the one thing support needs.
      expect(screen.getByTestId('state-error-request-id')).toHaveTextContent('req_abc123');
    });

    it('renders an ordinary message unchanged', () => {
      render(<ErrorState description="The service could not be reached." requestId="req_abc123" />);

      expect(screen.getByTestId('state-error')).toHaveTextContent('The service could not be reached.');
    });

    it('offers a retry when the caller can retry', async () => {
      const onRetry = vi.fn();
      render(<ErrorState description="Network failed." onRetry={onRetry} />);

      await userEvent.click(screen.getByRole('button', { name: 'Try again' }));

      expect(onRetry).toHaveBeenCalledOnce();
    });

    it('omits the request id line when there is none, rather than showing an empty label', () => {
      render(<ErrorState description="Network failed." />);

      expect(screen.queryByTestId('state-error-request-id')).not.toBeInTheDocument();
    });
  });

  it('renders offline keeping the last reading with its timestamp', () => {
    render(<OfflineState lastSeenAt="2 minutes ago" />);

    const region = screen.getByTestId(UNIVERSAL_STATES.offline.testId);
    expect(region.querySelector('[role="alert"]')).toBeInTheDocument();
    expect(screen.getByText(/Last reading: 2 minutes ago/)).toBeInTheDocument();
  });

  it('renders stale as "last observed …", never as a claim of health', () => {
    render(<StaleState observedAt="4 minutes ago" />);

    const region = screen.getByTestId(UNIVERSAL_STATES.stale.testId);
    expect(region).toHaveTextContent('Last observed 4 minutes ago');
    expect(region).not.toHaveTextContent(/healthy/i);
  });

  /**
   * AC7: no status is carried by colour alone. Asserted as text content rather
   * than as a class, because the question is what a colour-blind reader — or a
   * greyscale screenshot in an incident report — can still make out.
   */
  describe('none of them depends on colour', () => {
    it('gives every state a readable label', () => {
      const { rerender } = render(<NoPermissionState description="Restricted." />);
      expect(screen.getByTestId('state-no-permission').textContent).toMatch(/access/i);

      rerender(<OfflineState />);
      expect(screen.getByTestId('state-offline').textContent).toMatch(/unreachable/i);

      rerender(<StaleState observedAt="now" />);
      expect(screen.getByTestId('state-stale').textContent).toMatch(/last observed/i);

      rerender(<ErrorState description="Broken." />);
      expect(screen.getByTestId('state-error').textContent).toMatch(/went wrong/i);
    });

    it('marks decorative icons aria-hidden, so they are not read as content', () => {
      const { container } = render(<ErrorState description="Broken." />);

      const icons = container.querySelectorAll('svg');
      expect(icons.length).toBeGreaterThan(0);
      icons.forEach((icon) => expect(icon).toHaveAttribute('aria-hidden', 'true'));
    });
  });
});
