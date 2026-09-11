import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import ProjectPage from '@/pages/Panel/Project';

const usePage = vi.hoisted(() => vi.fn());
const patch = vi.hoisted(() => vi.fn());
const post = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  useForm: () => ({
    data: { name: 'Billing', slug: 'billing' },
    setData: vi.fn(),
    patch,
    processing: false,
  }),
  router: { visit: vi.fn(), delete: vi.fn(), post },
  Head: () => null,
  Link: ({ children, href, ...props }: React.ComponentProps<'a'>) => (
    <a href={href} {...props}>
      {children}
    </a>
  ),
}));

const SHELL_PROPS = {
  requestId: 'req_test',
  flash: { notice: null, alert: null },
  currentUser: { id: 'usr_01', name: 'Ana Lima', email: 'ana@example.test' },
  teams: [{ id: 'team_01', name: 'Acme', slug: 'acme', role: 'OWNER' }],
  currentTeam: { id: 'team_01', name: 'Acme', slug: 'acme', role: 'OWNER' },
};

const TEAM = { id: 'team_01', name: 'Acme', slug: 'acme' };

const PROJECT = {
  id: 'prj_01HX8Z9K3M4P5Q6R7S8T9V0W1X',
  name: 'Billing',
  slug: 'billing',
  description: null,
  status: 'ACTIVE',
  createdAt: '2026-09-09T12:00:00Z',
  updatedAt: '2026-09-09T12:00:00Z',
};

function renderPage(props: Partial<React.ComponentProps<typeof ProjectPage>> = {}) {
  usePage.mockReturnValue({ props: SHELL_PROPS });

  return render(
    <ProjectPage
      team={TEAM}
      project={PROJECT}
      permissions={{ update: true, archive: true }}
      {...props}
    />,
  );
}

describe('the project overview page', () => {
  beforeEach(() => {
    usePage.mockReset();
    patch.mockReset();
    post.mockReset();
  });

  it('renders inside the app shell', () => {
    renderPage();

    expect(screen.getByTestId('nav-projects')).toBeInTheDocument();
  });

  it('names the project and its URL name', () => {
    renderPage();

    expect(screen.getByRole('heading', { name: 'Billing' })).toBeInTheDocument();
    expect(screen.getByText('/billing')).toBeInTheDocument();
  });

  // doc 10 §25: no status is carried by colour alone.
  it('names the status in text', () => {
    renderPage({ project: { ...PROJECT, status: 'ARCHIVED' } });

    expect(screen.getByTestId('project-status')).toHaveTextContent('ARCHIVED');
  });

  it('shows a description when there is one, and no empty line when there is not', () => {
    const { unmount } = renderPage();
    expect(screen.queryByTestId('project-description')).not.toBeInTheDocument();
    unmount();

    renderPage({ project: { ...PROJECT, description: 'Invoices and dunning.' } });
    expect(screen.getByTestId('project-description')).toHaveTextContent('Invoices and dunning.');
  });

  describe('what it offers, and to whom', () => {
    it('offers the rename to an actor who may rename', async () => {
      renderPage();

      await userEvent.click(screen.getByRole('button', { name: /save changes/i }));

      expect(patch).toHaveBeenCalledWith(`/t/acme/projects/${PROJECT.id}`);
    });

    // The interface must not offer an action the server will refuse — the server
    // denies independently, so this is about not teaching the operator that the
    // UI lies.
    it('withholds the rename from an actor who may not', () => {
      renderPage({ permissions: { update: false, archive: true } });

      expect(screen.queryByRole('button', { name: /save changes/i })).not.toBeInTheDocument();
    });

    it('offers the archive to an actor who may archive', async () => {
      renderPage();

      await userEvent.click(screen.getByTestId('project-archive'));

      expect(post).toHaveBeenCalledWith(`/t/acme/projects/${PROJECT.id}/archive`);
    });

    it('withholds the archive from a DEVELOPER, who may rename and not archive', () => {
      renderPage({ permissions: { update: true, archive: false } });

      expect(screen.queryByTestId('project-archive')).not.toBeInTheDocument();
      expect(screen.getByRole('button', { name: /save changes/i })).toBeInTheDocument();
    });

    // Archiving twice is a conflict the server refuses; not offering it is how
    // the page stays honest about a state it can already see.
    it('does not offer to archive a project that already is', () => {
      renderPage({ project: { ...PROJECT, status: 'ARCHIVED' } });

      expect(screen.queryByTestId('project-archive')).not.toBeInTheDocument();
    });
  });

  describe('a failed submission', () => {
    const ERROR = {
      code: 'VALIDATION_ERROR',
      message: 'That URL name is already used.',
      requestId: 'req_abc',
    };

    it('shows the message and the request id', () => {
      renderPage({ error: ERROR });

      const alert = screen.getByTestId('project-error');
      expect(alert).toHaveTextContent('That URL name is already used.');
      expect(alert).toHaveTextContent('req_abc');
    });

    it('offers the free name the server suggested', () => {
      renderPage({ error: ERROR, suggestion: 'billing-2' });

      expect(screen.getByTestId('project-error')).toHaveTextContent('Try billing-2');
    });
  });
});
