import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';

import { PanelLayout } from '@/components/layouts/panel-layout';

/**
 * AC1: the authenticated user sees the app shell — asserted by **rendering** it.
 *
 * The first version of this Story tested the navigation order against the
 * exported constant and never mounted the layout, so `PanelLayout` was executed
 * by nothing at all: a shell that threw on render, or dropped the team switcher,
 * would have shipped with the suite green. Review caught it. These examples mount
 * the real component.
 */
const usePage = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  router: { visit: vi.fn(), delete: vi.fn() },
  Link: ({ children, href, ...props }: React.ComponentProps<'a'>) => (
    <a href={href} {...props}>
      {children}
    </a>
  ),
}));

const PROPS = {
  requestId: 'req_test',
  flash: { notice: null, alert: null },
  currentUser: { id: 'usr_01', name: 'Ana Lima', email: 'ana@example.test' },
  teams: [
    { id: 'team_01', name: 'Acme', slug: 'acme', role: 'OWNER' },
    { id: 'team_02', name: 'Beta Corp', slug: 'beta', role: 'DEVELOPER' },
  ],
  currentTeam: { id: 'team_01', name: 'Acme', slug: 'acme', role: 'OWNER' },
};

type ShellProps = {
  currentUser: (typeof PROPS)['currentUser'] | null;
  teams: (typeof PROPS)['teams'];
  currentTeam: (typeof PROPS)['currentTeam'] | null;
};

function renderShell(props: Partial<ShellProps> = {}) {
  usePage.mockReturnValue({ props: { ...PROPS, ...props } });

  return render(
    <PanelLayout section="projects">
      <p>Page body</p>
    </PanelLayout>,
  );
}

describe('the panel shell', () => {
  beforeEach(() => usePage.mockReset());

  it('renders the page it frames', () => {
    renderShell();

    expect(screen.getByText('Page body')).toBeInTheDocument();
  });

  it('shows the team switcher naming the current Team (AC1)', () => {
    renderShell();

    expect(screen.getByTestId('team-switcher')).toHaveTextContent('Acme');
  });

  it('shows the account menu (AC1)', () => {
    renderShell();

    // `shared/profile` renders the identity behind a trigger; the accessible name
    // is what a keyboard user reaches.
    expect(screen.getByRole('button', { name: /ana lima/i })).toBeInTheDocument();
  });

  /**
   * AC2, now against the rendered DOM rather than against the constant behind it.
   * A constant in the right order proves nothing if the component maps it wrong.
   */
  it('renders Projects before Clusters in the sidebar', () => {
    const { container } = renderShell();

    const order = Array.from(container.querySelectorAll('[data-testid^="nav-"]')).map((node) =>
      node.getAttribute('data-testid'),
    );

    expect(order).toEqual(['nav-projects', 'nav-clusters', 'nav-audit', 'nav-settings']);
  });

  it('points every navigation entry at the current Team', () => {
    renderShell();

    expect(screen.getByTestId('nav-projects')).toHaveAttribute('href', '/t/acme/projects');
    expect(screen.getByTestId('nav-clusters')).toHaveAttribute('href', '/t/acme/clusters');
  });

  it('follows the Team in the URL rather than the first one available', () => {
    renderShell({ currentTeam: PROPS.teams[1] });

    expect(screen.getByTestId('nav-projects')).toHaveAttribute('href', '/t/beta/projects');
  });

  /**
   * An account with no Team is a real state — one created after the installation
   * was bootstrapped has none. The shell must still render, and its links must go
   * somewhere the user can act rather than to `/t/undefined/…`.
   */
  it('survives an account with no Team', () => {
    renderShell({ teams: [], currentTeam: null });

    expect(screen.queryByTestId('team-switcher')).not.toBeInTheDocument();
    expect(screen.getByTestId('nav-projects')).toHaveAttribute('href', '/teams');
  });

  it('renders without an identity rather than throwing', () => {
    renderShell({ currentUser: null });

    expect(screen.getByText('Page body')).toBeInTheDocument();
  });

  // AC7: every navigation entry carries a word, not only an icon.
  it('labels every navigation entry in text', () => {
    renderShell();

    ['Projects', 'Clusters', 'Audit', 'Settings'].forEach((label) => {
      const entry = screen.getByTestId(`nav-${label.toLowerCase()}`);
      expect(within(entry).getByText(label)).toBeInTheDocument();
    });
  });
});
