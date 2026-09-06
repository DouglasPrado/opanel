import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

vi.mock('@inertiajs/react', () => ({
  Head: ({ children }: { children?: React.ReactNode }) => <>{children}</>,
  usePage: () => ({ props: { requestId: 'req-abc123', flash: { notice: null, alert: null } } }),
}));

const { default: Home } = await import('./Home');

describe('Home', () => {
  const platform = { name: 'Opanel', environment: 'test' };

  it('renders the props the server sent', () => {
    render(<Home platform={platform} />);

    expect(screen.getByRole('heading', { name: 'Opanel' })).toBeInTheDocument();
  });

  it('holds its disclosure in local state rather than asking the server', async () => {
    render(<Home platform={platform} />);

    const toggle = screen.getByRole('button', { name: 'Show details' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByTestId('platform-environment')).toBeNull();

    await userEvent.click(toggle);

    expect(screen.getByRole('button', { name: 'Hide details' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByTestId('platform-environment')).toHaveTextContent('test');
  });

  it('renders no error region when the server reported nothing', () => {
    render(<Home platform={platform} />);

    expect(screen.queryByTestId('page-error')).toBeNull();
  });

  it('renders the error the server reported, as an alert', () => {
    render(<Home platform={platform} error="The last rollout was rejected." />);

    const error = screen.getByTestId('page-error');
    expect(error).toHaveAttribute('role', 'alert');
    expect(error).toHaveTextContent('The last rollout was rejected.');
  });

  it('shows the request id so a failure can be quoted to support', () => {
    render(<Home platform={platform} />);

    expect(screen.getByTestId('request-id')).toHaveTextContent('req-abc123');
  });
});
