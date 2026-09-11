import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { TeamSwitcher, type TeamOption } from '@/components/shared/team-switcher';
import { PANEL_NAVIGATION } from '@/components/layouts/panel-layout';

const TEAMS: TeamOption[] = [
  { id: 'team_01', name: 'Acme', slug: 'acme', role: 'OWNER' },
  { id: 'team_02', name: 'Beta Corp', slug: 'beta', role: 'DEVELOPER' },
];

describe('the team switcher', () => {
  it('names the current Team on the trigger, so acting in the wrong one is visible', () => {
    render(<TeamSwitcher teams={TEAMS} currentTeamId="team_02" />);

    expect(screen.getByTestId('team-switcher')).toHaveTextContent('Beta Corp');
  });

  it('falls back to the first Team when none is current', () => {
    render(<TeamSwitcher teams={TEAMS} />);

    expect(screen.getByTestId('team-switcher')).toHaveTextContent('Acme');
  });

  it('says "No team" rather than rendering an empty control', () => {
    render(<TeamSwitcher teams={[]} />);

    expect(screen.getByTestId('team-switcher')).toHaveTextContent('No team');
  });

  it('lists every Team the actor may act in, with their role', async () => {
    render(<TeamSwitcher teams={TEAMS} currentTeamId="team_01" />);

    await userEvent.click(screen.getByTestId('team-switcher'));

    expect(screen.getByTestId('team-switcher-option-acme')).toHaveTextContent('OWNER');
    expect(screen.getByTestId('team-switcher-option-beta')).toHaveTextContent('DEVELOPER');
  });

  it('reports the selection to the caller', async () => {
    const onSelect = vi.fn();
    render(<TeamSwitcher teams={TEAMS} currentTeamId="team_01" onSelect={onSelect} />);

    await userEvent.click(screen.getByTestId('team-switcher'));
    await userEvent.click(screen.getByTestId('team-switcher-option-beta'));

    expect(onSelect).toHaveBeenCalledWith(TEAMS[1]);
  });

  // AC7 again, in the control where acting in the wrong Team is the silent
  // mistake: the current one is marked by an announced word, not only by an icon.
  it('marks the current Team for a screen reader, not only visually', async () => {
    render(<TeamSwitcher teams={TEAMS} currentTeamId="team_01" />);

    await userEvent.click(screen.getByTestId('team-switcher'));

    const current = screen.getByTestId('team-switcher-option-acme');
    expect(current).toHaveAttribute('aria-current', 'true');
    expect(current).toHaveTextContent('(current)');
    expect(screen.getByTestId('team-switcher-option-beta')).not.toHaveAttribute('aria-current');
  });

  // AC6: the menu is reachable and operable from the keyboard alone.
  it('opens and selects with the keyboard', async () => {
    const onSelect = vi.fn();
    render(<TeamSwitcher teams={TEAMS} currentTeamId="team_01" onSelect={onSelect} />);

    await userEvent.tab();
    expect(screen.getByTestId('team-switcher')).toHaveFocus();

    await userEvent.keyboard('{Enter}');
    expect(await screen.findByTestId('team-switcher-option-beta')).toBeInTheDocument();

    await userEvent.keyboard('{ArrowDown}{ArrowDown}{Enter}');
    expect(onSelect).toHaveBeenCalled();
  });
});

/**
 * AC2, asserted against the exported order rather than by reading the JSX. doc 10
 * §3 puts Projects before Clusters on purpose: a Project is what the operator
 * came to build, a Cluster is where it happens to run, and a sidebar that opens
 * with infrastructure teaches the wrong model.
 */
describe('the panel navigation', () => {
  it('puts Projects before Clusters', () => {
    const keys = PANEL_NAVIGATION.map((entry) => entry.key);

    expect(keys.indexOf('projects')).toBeLessThan(keys.indexOf('clusters'));
  });

  it('is exactly the sections doc 10 §3.2 gives M01', () => {
    expect(PANEL_NAVIGATION.map((entry) => entry.key)).toEqual([
      'projects',
      'clusters',
      'audit',
      'settings',
    ]);
  });

  it('gives every entry a label, so no icon stands alone', () => {
    PANEL_NAVIGATION.forEach((entry) => {
      expect(entry.label).toBeTruthy();
      expect(entry.label.length).toBeGreaterThan(2);
    });
  });
});
