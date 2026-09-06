import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from '@/components/ui/empty';
import { SkeletonCard } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';

import { expectStateRendered } from './support/render-state';
import { UNIVERSAL_STATES, type UniversalState } from './support/universal-states';

/**
 * The universal states of doc 10 §25, each rendered with the imported library
 * rather than with something written here — that is the point of having imported
 * it. These are the examples every following UI Story copies from.
 */
describe('universal UI states', () => {
  it('renders loading as a skeleton of the structure', () => {
    const region = expectStateRendered(
      'loading',
      <div role="status" aria-label="Loading services">
        <SkeletonCard />
      </div>,
    );

    expect(region).toHaveTextContent('');
    expect(screen.getByRole('status')).toHaveAccessibleName('Loading services');
  });

  it('renders empty with the value it offers and a call to action', () => {
    expectStateRendered(
      'empty',
      <Empty>
        <EmptyHeader>
          <EmptyTitle>No services yet</EmptyTitle>
          <EmptyDescription>Deploy an image to see it running here.</EmptyDescription>
        </EmptyHeader>
        <Button size="sm">Deploy a service</Button>
      </Empty>,
    );

    expect(screen.getByText('No services yet')).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Deploy a service' }),
      'an empty state without a call to action leaves the user with nowhere to go',
    ).toBeInTheDocument();
  });

  it('renders an error without leaking what caused it', () => {
    render(
      <Alert variant="destructive">
        <AlertTitle>Rollout failed</AlertTitle>
        <AlertDescription>Request 3f2a-91bd. Quote it when reporting this.</AlertDescription>
      </Alert>,
    );

    const alert = screen.getByRole('alert');

    expect(alert).toHaveTextContent('Rollout failed');
    expect(alert).toHaveTextContent('3f2a-91bd');
    expect(alert.textContent).not.toMatch(/SELECT|\/app\/|Traceback|at .*\.rb:\d+/);
  });

  it('renders no-permission without revealing the data behind it', () => {
    expectStateRendered(
      'no-permission',
      <Alert role="alert">
        <AlertTitle>You do not have access to this environment</AlertTitle>
        <AlertDescription>Ask an owner of this team for access.</AlertDescription>
      </Alert>,
    );

    expect(screen.getByRole('alert').textContent).not.toMatch(/svc_|prj_|sha256:/);
  });

  it('renders offline while preserving the last reading and its timestamp', () => {
    expectStateRendered(
      'offline',
      <Alert role="alert">
        <AlertTitle>Control Plane unreachable</AlertTitle>
        <AlertDescription>Last observed 12:04 UTC. Changes are blocked.</AlertDescription>
      </Alert>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('Last observed');
  });

  it('renders stale as an observation age, not as health', () => {
    expectStateRendered('stale', <Badge variant="secondary">last observed 4m ago</Badge>);

    expect(screen.getByText(/last observed/)).toBeInTheDocument();
    expect(screen.queryByText(/^Healthy$/)).toBeNull();
  });

  it('renders operation-running with the primary action disabled', () => {
    expectStateRendered(
      'operation-running',
      <Button size="sm" disabled>
        Scaling…
      </Button>,
    );

    expect(screen.getByRole('button', { name: 'Scaling…' })).toBeDisabled();
  });

  it('renders partial failure as parts, not as a bare failure', () => {
    expectStateRendered(
      'partial-failure',
      <Alert role="alert">
        <AlertTitle>7/8 replicas healthy</AlertTitle>
        <AlertDescription>One task is restarting on node-c.</AlertDescription>
      </Alert>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('7/8');
  });

  it('renders deleted as read-only during retention', () => {
    expectStateRendered('deleted', <Badge variant="secondary">archived · read-only</Badge>);

    expect(screen.getByText(/read-only/)).toBeInTheDocument();
  });

  it('covers every state doc 10 §25 defines', () => {
    const covered: UniversalState[] = [
      'loading',
      'empty',
      'no-permission',
      'offline',
      'stale',
      'operation-running',
      'partial-failure',
      'deleted',
    ];

    expect(covered.sort()).toEqual((Object.keys(UNIVERSAL_STATES) as UniversalState[]).sort());
  });
});
