import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

import Environments, { ENVIRONMENT_TYPES } from '@/pages/Panel/Environments';

/**
 * The Environments page, mounted.
 *
 * AC8 requires the PRODUCTION badge to be visible and unchanging,
 * so a reader cannot mistake which Environment they are operating on during
 * an incident. This tests that the badge renders correctly for production
 * and non-production environment types.
 */
const usePage = vi.hoisted(() => vi.fn());
const post = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  useForm: () => ({
    data: { name: '', slug: '', cluster_id: '', type: 'DEVELOPMENT' },
    setData: vi.fn(),
    post,
    processing: false,
    errors: {},
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

const mockTeam = {
  id: 'team_123',
  name: 'Test Team',
  slug: 'test-team',
};

const mockProject = {
  id: 'prj_123',
  name: 'Test Project',
  slug: 'test-project',
};

const mockClusters = [
  { id: 'cl_123', name: 'Primary', slug: 'primary' },
];

function renderPage(props: Partial<React.ComponentProps<typeof Environments>> = {}) {
  usePage.mockReturnValue({ props: SHELL_PROPS });

  return render(
    <Environments
      team={mockTeam}
      project={mockProject}
      environments={[]}
      clusters={mockClusters}
      permissions={{ create: true }}
      {...props}
    />
  );
}

describe('Environments Page', () => {
  beforeEach(() => {
    usePage.mockReset();
    post.mockReset();
  });

  it('renders a PRODUCTION badge for production environments', () => {
    renderPage({
      environments: [
        {
          id: 'env_prod',
          name: 'Production',
          slug: 'prod',
          type: 'PRODUCTION',
          status: 'READY',
          clusterName: 'Primary',
          createdAt: '2026-09-10T12:00:00Z',
        },
      ],
    });

    const badge = screen.getByTestId('environment-badge');
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveAttribute('data-environment', 'PRODUCTION');
    // Badge should be in a table row with the environment name
    const row = screen.getByTestId('environment-row-env_prod');
    expect(row).toBeInTheDocument();
    expect(row).toHaveTextContent('Production');
  });

  it('does not render a PRODUCTION badge for non-production environments', () => {
    renderPage({
      environments: [
        {
          id: 'env_dev',
          name: 'Development',
          slug: 'dev',
          type: 'DEVELOPMENT',
          status: 'READY',
          clusterName: 'Primary',
          createdAt: '2026-09-10T12:00:00Z',
        },
      ],
    });

    const badge = screen.getByTestId('environment-badge');
    expect(badge).toBeInTheDocument();
    expect(badge).toHaveAttribute('data-environment', 'DEVELOPMENT');
    // DEVELOPMENT badge should not have the alert icon that PRODUCTION gets
    expect(badge.querySelector('svg')).not.toBeInTheDocument();
  });

  it('offers exactly the five environment types the schema accepts', () => {
    // AC5: The UI must support all types the backend schema accepts.
    // This guards against regressions like using STAGING instead of HOMOLOGATION,
    // or omitting CUSTOM. The form maps over this constant to build its options,
    // so if it changes, the rendered options change automatically.
    expect([...ENVIRONMENT_TYPES].sort()).toEqual(
      ['CUSTOM', 'DEVELOPMENT', 'HOMOLOGATION', 'PREVIEW', 'PRODUCTION'].sort()
    );
  });

  it('renders the correct badge for each environment type', () => {
    // Verify the badge component handles all five types without errors
    for (const type of ENVIRONMENT_TYPES) {
      const { unmount } = renderPage({
        environments: [
          {
            id: `env_${type}`,
            name: type,
            slug: type.toLowerCase(),
            type,
            status: 'READY',
            clusterName: 'Primary',
            createdAt: '2026-09-10T12:00:00Z',
          },
        ],
      });
      expect(screen.getByTestId(`environment-row-env_${type}`)).toBeInTheDocument();
      expect(screen.getByTestId('environment-badge')).toHaveAttribute('data-environment', type);
      unmount();
    }
  });
});
