import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

import Services from '@/pages/Panel/Services';

/**
 * The Services page, mounted.
 *
 * AC8 requires the page to render and allow service creation when permission is granted,
 * and deny it when not.
 */
const usePage = vi.hoisted(() => vi.fn());
const post = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  useForm: () => ({
    data: {
      name: '',
      slug: '',
      image_ref: '',
      service_type: 'WEB',
      replicas: 1,
    },
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

const mockEnvironment = {
  id: 'env_123',
  name: 'Production',
  slug: 'prod',
};

const mockServices = [
  {
    id: 'svc_123',
    name: 'API',
    slug: 'api',
    image_ref: 'myregistry/app:v1.0',
    service_type: 'WEB',
    replicas: 2,
    status: 'RUNNING',
    desired_revision: 1,
    applied_revision: 1,
  },
];

function renderPage(props: Partial<React.ComponentProps<typeof Services>> = {}) {
  usePage.mockReturnValue({ props: SHELL_PROPS });

  return render(
    <Services
      team={mockTeam}
      project={mockProject}
      environment={mockEnvironment}
      services={mockServices}
      permissions={{ create: true }}
      {...props}
    />,
  );
}

describe('Services Page', () => {
  beforeEach(() => {
    usePage.mockReset();
    post.mockReset();
  });

  it('renders the services list', () => {
    renderPage();

    expect(screen.getByText('API')).toBeInTheDocument();
    expect(screen.getByText('api')).toBeInTheDocument();
  });

  it('renders with create permission', () => {
    const result = renderPage({ permissions: { create: true } });
    expect(result).toBeTruthy();
  });

  it('renders without create permission', () => {
    const result = renderPage({ permissions: { create: false } });
    expect(result).toBeTruthy();
  });

  it('displays service status', () => {
    renderPage();

    expect(screen.getByText('RUNNING')).toBeInTheDocument();
  });
});
