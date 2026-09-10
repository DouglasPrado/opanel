import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import Clusters from '@/pages/Panel/Clusters';

const usePage = vi.hoisted(() => vi.fn());
const post = vi.hoisted(() => vi.fn());
const routerPost = vi.hoisted(() => vi.fn());

vi.mock('@inertiajs/react', () => ({
  usePage,
  useForm: () => ({
    data: { name: 'Production', slug: '', advertiseAddress: '10.0.0.5', adoptExisting: false },
    setData: vi.fn(),
    post,
    processing: false,
  }),
  router: { visit: vi.fn(), delete: vi.fn(), post: routerPost },
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

const CLUSTER = {
  id: 'cl_01HX8Z9K3M4P5Q6R7S8T9V0W1X',
  name: 'Production',
  slug: 'production',
  status: 'READY',
  swarmId: 'abcdefghij0123456789k',
  advertiseAddress: '10.0.0.5',
  observedAt: '2026-09-09T12:00:00Z',
  stale: false,
  unreachableReason: null,
  operational: true,
  highlyAvailable: false,
  checks: [
    { name: 'swarm', status: 'HEALTHY' as const, detail: 'abcdefghij0123456789k' },
    { name: 'manager', status: 'HEALTHY' as const, detail: '1 manager, no quorum yet' },
  ],
  nodes: [],
  permissions: { refresh: true },
};

const PREFLIGHT = {
  checks: [
    { name: 'operating_system', status: 'PASS' as const, detail: 'linux x86_64' },
    { name: 'clock', status: 'FAIL' as const, detail: 'the system clock is not synchronized' },
    { name: 'disk_space', status: 'UNKNOWN' as const, detail: 'could not measure free space' },
  ],
  candidates: [{ name: 'eth0', address: '10.0.0.5', private: true }],
  suggested: '10.0.0.5',
  choiceRequired: false,
  blocked: true,
};

function renderPage(props: Partial<React.ComponentProps<typeof Clusters>> = {}) {
  usePage.mockReturnValue({ props: SHELL_PROPS });

  return render(
    <Clusters team={TEAM} clusters={[]} permissions={{ bootstrap: true }} {...props} />,
  );
}

describe('the clusters page', () => {
  beforeEach(() => {
    usePage.mockReset();
    post.mockReset();
    routerPost.mockReset();
  });

  it('renders inside the app shell', () => {
    renderPage();

    expect(screen.getByTestId('nav-clusters')).toBeInTheDocument();
  });

  it('shows the shared empty state before anything is bootstrapped', () => {
    renderPage();

    expect(screen.getByTestId('state-empty')).toHaveTextContent(/cluster/i);
  });

  describe('the readiness checks (AC3)', () => {
    it('reports every check by name with its status as a word', () => {
      renderPage({ preflight: PREFLIGHT });

      expect(
        within(screen.getByTestId('check-operating_system')).getByText('PASS'),
      ).toBeInTheDocument();
      expect(within(screen.getByTestId('check-clock')).getByText('FAIL')).toBeInTheDocument();
    });

    // A check the machine could not evaluate is not a check that passed. Showing
    // it as a tick is how a bootstrap proceeds on a machine nobody verified.
    it('renders UNKNOWN as itself, never as a pass', () => {
      renderPage({ preflight: PREFLIGHT });

      const check = screen.getByTestId('check-disk_space');
      expect(check).toHaveTextContent('UNKNOWN');
      expect(check).not.toHaveTextContent('PASS');
    });

    it('shows the detail next to each check, so the operator knows what to fix', () => {
      renderPage({ preflight: PREFLIGHT });

      expect(screen.getByTestId('check-clock')).toHaveTextContent(
        'the system clock is not synchronized',
      );
    });

    // AC4 in the interface: a blocked machine cannot be bootstrapped from here.
    it('disables the bootstrap while a check is failing', () => {
      renderPage({ preflight: PREFLIGHT });

      expect(screen.getByRole('button', { name: /initialize cluster/i })).toBeDisabled();
      expect(screen.getByTestId('preflight-blocked')).toBeInTheDocument();
    });

    it('allows it once nothing is failing', () => {
      renderPage({ preflight: { ...PREFLIGHT, blocked: false, checks: [PREFLIGHT.checks[0]] } });

      expect(screen.getByRole('button', { name: /initialize cluster/i })).toBeEnabled();
      expect(screen.queryByTestId('preflight-blocked')).not.toBeInTheDocument();
    });
  });

  describe('the advertise address (AC5)', () => {
    it('says the choice is required when the machine has several addresses', () => {
      renderPage({
        preflight: {
          ...PREFLIGHT,
          blocked: false,
          choiceRequired: true,
          suggested: null,
          candidates: [
            { name: 'eth0', address: '10.0.0.5', private: true },
            { name: 'eth1', address: '192.168.9.9', private: true },
          ],
        },
      });

      expect(screen.getByLabelText(/advertise address/i)).toBeRequired();
      expect(screen.getByText(/it is not guessed/i)).toBeInTheDocument();
    });

    it('offers the detected addresses as options', () => {
      const { container } = renderPage({ preflight: PREFLIGHT });

      const options = Array.from(container.querySelectorAll('#advertise-candidates option'));
      expect(options.map((option) => option.getAttribute('value'))).toEqual(['10.0.0.5']);
    });
  });

  describe('what it shows about a cluster', () => {
    it('names the status in text, never only by colour', () => {
      renderPage({ clusters: [CLUSTER] });

      expect(screen.getByTestId('cluster-status-production')).toHaveTextContent('READY');
    });

    // doc 06 §14.1: operational is not the same question as highly available, and
    // an operator who is not told assumes.
    it('says a single-node cluster has no high availability', () => {
      renderPage({ clusters: [CLUSTER] });

      expect(screen.getByTestId('cluster-list')).toHaveTextContent('No HA — single node');
    });

    // doc 10 §25's stale state: "last observed …", never a claim of health.
    it('presents a stale reading as last observed, not as current', () => {
      renderPage({ clusters: [{ ...CLUSTER, stale: true, operational: false }] });

      expect(screen.getByTestId('observed-production')).toHaveTextContent('Last observed');
      expect(screen.getByTestId('cluster-list')).toHaveTextContent('Not operational');
    });

    it('presents a fresh reading without the stale wording', () => {
      renderPage({ clusters: [CLUSTER] });

      expect(screen.getByTestId('observed-production')).not.toHaveTextContent('Last observed');
    });

    // AC7 reaching the screen: the cause is named, not a generic failure.
    it('names the classified cause of an unreachable cluster', () => {
      renderPage({
        clusters: [
          {
            ...CLUSTER,
            status: 'UNREACHABLE',
            operational: false,
            unreachableReason: 'DAEMON_UNREACHABLE',
          },
        ],
      });

      expect(screen.getByTestId('reason-production')).toHaveTextContent('DAEMON_UNREACHABLE');
    });

    it('offers a fresh reading to whoever may take one', async () => {
      renderPage({ clusters: [CLUSTER] });

      await userEvent.click(screen.getByTestId('refresh-production'));

      expect(routerPost).toHaveBeenCalledWith(`/t/acme/clusters/${CLUSTER.id}/refresh`);
    });

    it('withholds it from somebody who may not', () => {
      renderPage({ clusters: [{ ...CLUSTER, permissions: { refresh: false } }] });

      expect(screen.queryByTestId('refresh-production')).not.toBeInTheDocument();
    });
  });

  describe('nodes and staleness (AC4, AC5)', () => {
    it('displays nodes with role, availability, status, and lastSeenAt', () => {
      const clusterWithNodes = {
        ...CLUSTER,
        nodes: [
          {
            id: 'node_01',
            swarmNodeId: 'node1abc',
            hostname: 'manager-1',
            role: 'MANAGER',
            availability: 'ACTIVE',
            status: 'READY',
            advertiseAddress: '10.0.0.1',
            lastSeenAt: '2026-09-09T12:00:00Z',
            stale: false,
          },
        ],
      };

      renderPage({ clusters: [clusterWithNodes] });

      expect(screen.getByTestId('node-node1abc')).toBeInTheDocument();
      expect(screen.getByText('manager-1')).toBeInTheDocument();
      expect(screen.getByText('MANAGER')).toBeInTheDocument();
      expect(screen.getByText('ACTIVE')).toBeInTheDocument();
    });

    // doc 10 §25: a node without a recent observation must NOT render as healthy.
    // The UI shows it is stale and the row dims.
    it('marks a stale node with a stale badge and dims the row', () => {
      const clusterWithStaleNode = {
        ...CLUSTER,
        nodes: [
          {
            id: 'node_01',
            swarmNodeId: 'node1abc',
            hostname: 'manager-1',
            role: 'MANAGER',
            availability: 'ACTIVE',
            status: 'READY',
            advertiseAddress: '10.0.0.1',
            lastSeenAt: '2026-09-08T12:00:00Z',
            stale: true,
          },
        ],
      };

      renderPage({ clusters: [clusterWithStaleNode] });

      const nodeRow = screen.getByTestId('node-node1abc');
      expect(nodeRow).toHaveClass('opacity-60');
      // The stale badge should appear separately next to the status badge
      expect(nodeRow.querySelector('[data-testid="node-status-node1abc"]')).toHaveTextContent('READY');
      expect(nodeRow).toHaveTextContent('stale');
      expect(nodeRow).toHaveTextContent('Last seen');
    });

    it('shows fresh nodes without stale marking', () => {
      const clusterWithFreshNode = {
        ...CLUSTER,
        nodes: [
          {
            id: 'node_01',
            swarmNodeId: 'node1abc',
            hostname: 'manager-1',
            role: 'MANAGER',
            availability: 'ACTIVE',
            status: 'READY',
            advertiseAddress: '10.0.0.1',
            lastSeenAt: '2026-09-09T12:00:00Z',
            stale: false,
          },
        ],
      };

      renderPage({ clusters: [clusterWithFreshNode] });

      const nodeRow = screen.getByTestId('node-node1abc');
      expect(nodeRow).not.toHaveClass('opacity-60');
      expect(screen.queryByTestId('node-status-node1abc')).not.toHaveTextContent('stale');
      expect(nodeRow).toHaveTextContent('Seen 2026-09-09T12:00:00Z');
    });
  });

  describe('what it offers, and to whom', () => {
    it('withholds the bootstrap from somebody who may not run it', () => {
      renderPage({ permissions: { bootstrap: false } });

      expect(screen.queryByRole('button', { name: /initialize cluster/i })).not.toBeInTheDocument();
      expect(screen.queryByTestId('run-preflight')).not.toBeInTheDocument();
    });

    it('posts the bootstrap to the team the page is about', async () => {
      renderPage({ preflight: { ...PREFLIGHT, blocked: false } });

      await userEvent.click(screen.getByRole('button', { name: /initialize cluster/i }));

      expect(post).toHaveBeenCalledWith('/t/acme/clusters');
    });
  });

  describe('a failed bootstrap', () => {
    const ERROR = {
      code: 'PREFLIGHT_FAILED',
      message: 'The machine is not ready.',
      requestId: 'req_abc',
    };

    it('names the checks that failed', () => {
      renderPage({
        error: ERROR,
        details: { failedChecks: [{ name: 'clock', detail: 'not synchronized' }] },
      });

      expect(screen.getByTestId('failed-checks')).toHaveTextContent('clock');
      expect(screen.getByTestId('failed-checks')).toHaveTextContent('not synchronized');
    });

    it('shows the classified cause of an unreachable daemon, with the request id', () => {
      renderPage({
        error: { code: 'ENGINE_UNAVAILABLE', message: 'docker info failed', requestId: 'req_abc' },
        details: { cause: 'DAEMON_UNREACHABLE' },
      });

      const alert = screen.getByTestId('clusters-error');
      expect(alert).toHaveTextContent('DAEMON_UNREACHABLE');
      expect(alert).toHaveTextContent('req_abc');
    });

    it('lists the candidate addresses when a choice was required', () => {
      renderPage({
        error: { code: 'VALIDATION_ERROR', message: 'Choose an address.', requestId: 'req_abc' },
        details: { candidates: ['10.0.0.5', '192.168.9.9'] },
      });

      expect(screen.getByTestId('clusters-error')).toHaveTextContent('10.0.0.5, 192.168.9.9');
    });
  });

  // AC8, from the browser's side: the page has no Engine address and no field
  // that accepts one.
  it('carries no Docker endpoint anywhere on the page', () => {
    const { container } = renderPage({ clusters: [CLUSTER], preflight: PREFLIGHT });

    expect(container.innerHTML).not.toContain('2375');
    expect(container.innerHTML).not.toContain('docker.sock');
    expect(container.innerHTML).not.toContain('DOCKER_HOST');
  });
});
