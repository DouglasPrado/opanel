import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { SessionList, type SessionListEntry } from './session-list';

function entry(overrides: Partial<SessionListEntry> = {}): SessionListEntry {
  return {
    id: 'ses_01HX8Z9K3M4P5Q6R7S8T9V0W1X',
    current: false,
    active: true,
    ipAddress: '203.0.113.5',
    userAgent: 'Chrome on macOS',
    lastSeenAt: '2026-09-09T10:00:00Z',
    createdAt: '2026-09-01T10:00:00Z',
    expiresAt: '2026-09-16T10:00:00Z',
    revokedAt: null,
    ...overrides,
  };
}

describe('SessionList', () => {
  it('renders one row per session', () => {
    render(
      <SessionList
        sessions={[entry(), entry({ id: 'ses_01HX8Z9K3M4P5Q6R7S8T9V0W2Y', userAgent: 'Firefox' })]}
        onRevoke={vi.fn()}
      />,
    );

    expect(screen.getAllByTestId('session-item')).toHaveLength(2);
    expect(screen.getByText('Chrome on macOS')).toBeInTheDocument();
    expect(screen.getByText('Firefox')).toBeInTheDocument();
  });

  it('shows the device metadata and when the session was last seen', () => {
    render(<SessionList sessions={[entry()]} onRevoke={vi.fn()} />);

    const item = screen.getByTestId('session-item');

    expect(within(item).getByText(/203\.0\.113\.5/)).toBeInTheDocument();
    expect(within(item).getByTestId('session-last-seen')).toHaveAttribute(
      'dateTime',
      '2026-09-09T10:00:00Z',
    );
  });

  it('names a device the server could not identify rather than rendering a blank row', () => {
    render(
      <SessionList sessions={[entry({ userAgent: null, ipAddress: null })]} onRevoke={vi.fn()} />,
    );

    expect(screen.getByTestId('session-item')).toHaveTextContent(/unknown device/i);
  });

  it('marks the session making the request, and offers no way to revoke it by mistake', () => {
    render(
      <SessionList
        sessions={[entry({ current: true }), entry({ id: 'ses_01HX8Z9K3M4P5Q6R7S8T9V0W2Y' })]}
        onRevoke={vi.fn()}
      />,
    );

    const [current] = screen.getAllByTestId('session-item');

    expect(within(current).getByText(/this device/i)).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: /sign out|revoke/i })).toHaveLength(2);
  });

  it('renders an empty state instead of an empty list', () => {
    render(<SessionList sessions={[]} onRevoke={vi.fn()} />);

    expect(screen.queryAllByTestId('session-item')).toHaveLength(0);
    expect(screen.getByText(/no other sessions|no active sessions/i)).toBeInTheDocument();
  });

  it('does not offer to revoke a session that is already revoked', () => {
    render(
      <SessionList
        sessions={[entry({ active: false, revokedAt: '2026-09-08T10:00:00Z' })]}
        onRevoke={vi.fn()}
      />,
    );

    expect(screen.queryByRole('button', { name: /revoke/i })).toBeNull();
    expect(screen.getByTestId('session-item')).toHaveTextContent(/revoked/i);
  });

  it('confirms before revoking, because a revocation cannot be undone', async () => {
    const onRevoke = vi.fn();
    render(<SessionList sessions={[entry()]} onRevoke={onRevoke} />);

    await userEvent.click(screen.getByRole('button', { name: /revoke/i }));

    expect(onRevoke).not.toHaveBeenCalled();
    expect(await screen.findByRole('alertdialog')).toBeInTheDocument();
  });

  it('revokes by identifier once the confirmation is accepted', async () => {
    const onRevoke = vi.fn();
    render(<SessionList sessions={[entry()]} onRevoke={onRevoke} />);

    await userEvent.click(screen.getByRole('button', { name: /revoke/i }));
    const dialog = await screen.findByRole('alertdialog');
    await userEvent.click(within(dialog).getByRole('button', { name: /revoke/i }));

    expect(onRevoke).toHaveBeenCalledWith('ses_01HX8Z9K3M4P5Q6R7S8T9V0W1X');
  });

  it('does not revoke when the confirmation is dismissed', async () => {
    const onRevoke = vi.fn();
    render(<SessionList sessions={[entry()]} onRevoke={onRevoke} />);

    await userEvent.click(screen.getByRole('button', { name: /revoke/i }));
    const dialog = await screen.findByRole('alertdialog');
    await userEvent.click(within(dialog).getByRole('button', { name: /cancel|keep/i }));

    expect(onRevoke).not.toHaveBeenCalled();
  });

  it('disables the control while a revocation is in flight', () => {
    render(
      <SessionList
        sessions={[entry()]}
        onRevoke={vi.fn()}
        revokingId="ses_01HX8Z9K3M4P5Q6R7S8T9V0W1X"
      />,
    );

    expect(screen.getByRole('button', { name: /revoking/i })).toBeDisabled();
  });

  it('renders no credential, whatever the server sent', () => {
    const { container } = render(<SessionList sessions={[entry()]} onRevoke={vi.fn()} />);

    expect(container.innerHTML).not.toMatch(/tokenDigest|token_digest/i);
  });
});
