import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import Projects from '@/pages/Panel/Projects';

/**
 * The Projects page, mounted.
 *
 * Mounting rather than asserting on the props it would receive: `M01-06` shipped
 * a navigation test that read the exported constant and never rendered the
 * layout, so a component that threw on render would have passed. Review caught
 * it there; this file does not repeat it.
 */
const usePage = vi.hoisted(() => vi.fn());
const post = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  // A name already typed: the field is `required`, and jsdom runs constraint
  // validation before it dispatches `submit`. An empty form never reaches the
  // handler — which is correct, and would have made this example assert
  // nothing.
  useForm: () => ({
    data: { name: 'Billing Ops', slug: '' },
    setData: vi.fn(),
    post,
    processing: false,
  }),
  router: { visit: vi.fn(), delete: vi.fn() },
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
  name: 'Billing Ops',
  slug: 'billing-ops',
  description: null,
  status: 'ACTIVE',
  createdAt: '2026-09-09T12:00:00Z',
};

function renderPage(props: Partial<React.ComponentProps<typeof Projects>> = {}) {
  usePage.mockReturnValue({ props: SHELL_PROPS });

  return render(<Projects team={TEAM} projects={[]} permissions={{ create: true }} {...props} />);
}

describe('the projects page', () => {
  beforeEach(() => {
    usePage.mockReset();
    post.mockReset();
  });

  it('renders inside the app shell', () => {
    renderPage();

    expect(screen.getByTestId('nav-projects')).toBeInTheDocument();
  });

  // doc 10 §25: an empty state is a required state, and it says what the section
  // is for rather than only that it is empty.
  it('shows the shared empty state, not a blank page, when there is nothing yet', () => {
    renderPage();

    const empty = screen.getByTestId('state-empty');
    expect(empty).toBeInTheDocument();
    expect(empty).toHaveTextContent(/project/i);
  });

  it('lists the projects it is given', () => {
    renderPage({ projects: [PROJECT] });

    expect(screen.getByTestId('project-billing-ops')).toHaveTextContent('Billing Ops');
    expect(screen.queryByTestId('state-empty')).not.toBeInTheDocument();
  });

  // Without this the overview is reachable only right after creating a Project,
  // or by typing the URL — so renaming an *existing* one has no click path at
  // all. Review found it; the assertion is on the `href`, not on the text, so a
  // card that renders the name and links nowhere fails.
  it('links each project to its overview', () => {
    renderPage({ projects: [PROJECT] });

    expect(screen.getByTestId('project-billing-ops')).toHaveAttribute(
      'href',
      `/t/acme/projects/${PROJECT.id}`,
    );
  });

  // AC7 of M01-06, still true here: the status is a word, never only a colour.
  it('names the status in text', () => {
    renderPage({ projects: [{ ...PROJECT, status: 'ARCHIVED' }] });

    expect(screen.getByTestId('project-list')).toHaveTextContent('ARCHIVED');
  });

  describe('the create form', () => {
    it('is offered to an actor who may create', () => {
      renderPage();

      expect(screen.getByRole('button', { name: /create project/i })).toBeInTheDocument();
    });

    // The UI must not offer an action the server will refuse. The server denies
    // independently — this is about not teaching the operator that the interface
    // lies.
    it('is withheld from an actor who may not', () => {
      renderPage({ permissions: { create: false } });

      expect(screen.queryByRole('button', { name: /create project/i })).not.toBeInTheDocument();
    });

    it('posts to the team the page is about', async () => {
      renderPage();

      await userEvent.click(screen.getByRole('button', { name: /create project/i }));

      expect(post).toHaveBeenCalledWith('/t/acme/projects');
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

      const alert = screen.getByTestId('projects-error');
      expect(alert).toHaveTextContent('That URL name is already used.');
      expect(alert).toHaveTextContent('req_abc');
    });

    it('offers the free name the server suggested', () => {
      renderPage({ error: ERROR, suggestion: 'billing-2' });

      expect(screen.getByTestId('projects-error')).toHaveTextContent('Try billing-2');
    });

    // The form is re-rendered, not replaced: the list the user was looking at is
    // still there.
    it('keeps the list it was showing', () => {
      renderPage({ error: ERROR, projects: [PROJECT] });

      expect(screen.getByTestId('project-billing-ops')).toBeInTheDocument();
    });
  });

  describe('paging', () => {
    it('offers more only when the server said there is more', () => {
      renderPage({ projects: [PROJECT] });
      expect(screen.queryByTestId('projects-next')).not.toBeInTheDocument();
    });

    it('carries the cursor the server returned', () => {
      renderPage({ projects: [PROJECT], nextCursor: 'prj_02' });

      // `asChild` collapses the Button into the anchor, so the test id is on the
      // link itself — which is also what a keyboard user tabs to.
      expect(screen.getByTestId('projects-next')).toHaveAttribute(
        'href',
        '/t/acme/projects?cursor=prj_02',
      );
    });
  });
});
