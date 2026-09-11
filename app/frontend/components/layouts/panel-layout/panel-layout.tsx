import type { ReactNode } from 'react';
import { Link, router, usePage } from '@inertiajs/react';

import {
  AppShell,
  AppShellContent,
  AppShellMain,
  AppShellNavbar,
  AppShellSidebar,
  AppShellTrigger,
} from '@/components/layouts/app-shell';
import {
  SidebarContent,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/layouts/sidebar';
import { Profile } from '@/components/shared/profile';
import { TeamSwitcher } from '@/components/shared/team-switcher';
import { Icons } from '@/components/ui/icons';

/**
 * The frame every authenticated page of the Control Plane renders inside.
 *
 * ## Reuse Gate
 *
 * Composes `app-shell`, `sidebar`, `profile` and the `team-switcher` this Story
 * adds. No new primitive, no second shell: the inventory's `app-shell` row says
 * it is for "every authenticated page", and this is the one place that says how.
 * Sign-in, sign-up and the error page deliberately do **not** use it — the same
 * row says so, and a shell around a sign-in form offers navigation the visitor
 * cannot use.
 *
 * ## Why the order of the sidebar is a decision and not a preference
 *
 * doc 10 §3 puts `Projects` before `Clusters` (AC2), and the reason is that the
 * information architecture teaches the model: a Project is what the user came to
 * build, a Cluster is where it happens to run. A sidebar that opens with
 * infrastructure tells them this is a Docker console with extra steps.
 */
const NAVIGATION = [
  { key: 'projects', label: 'Projects', icon: Icons.rocket, path: 'projects' },
  { key: 'clusters', label: 'Clusters', icon: Icons.grid, path: 'clusters' },
  { key: 'audit', label: 'Audit', icon: Icons.book, path: 'audit' },
  { key: 'settings', label: 'Settings', icon: Icons.cog, path: 'settings' },
] as const;

export type PanelSection = (typeof NAVIGATION)[number]['key'];

export function PanelLayout({
  children,
  section,
}: {
  children: ReactNode;
  section?: PanelSection;
}) {
  const page = usePage();
  const { currentUser, teams = [], currentTeam } = page.props;

  const teamSlug = currentTeam?.slug ?? teams[0]?.slug;

  return (
    <AppShell>
      <AppShellNavbar>
        <div className="flex h-full w-full items-center gap-3 px-4">
          <AppShellTrigger />

          <Link href="/" className="flex items-center gap-2 font-semibold" aria-label="Opanel home">
            <Icons.logo className="size-6" aria-hidden="true" />
            <span className="hidden sm:inline">Opanel</span>
          </Link>

          {teams.length > 0 ? (
            <TeamSwitcher
              teams={teams}
              currentTeamId={currentTeam?.id}
              onSelect={(team) => router.visit(`/t/${team.slug}/projects`)}
              className="ml-2"
            />
          ) : null}

          <div className="ml-auto flex items-center gap-2">
            {currentUser ? (
              <Profile
                name={currentUser.name}
                email={currentUser.email}
                fallback={currentUser.name.slice(0, 2).toUpperCase()}
                onSettings={() => router.visit('/settings/sessions')}
                onLogout={() => router.delete('/sign_out')}
              />
            ) : null}
          </div>
        </div>
      </AppShellNavbar>

      <AppShellSidebar>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Platform</SidebarGroupLabel>
            <SidebarMenu>
              {NAVIGATION.map((entry) => {
                const Icon = entry.icon;
                const href = teamSlug ? `/t/${teamSlug}/${entry.path}` : '/teams';

                return (
                  <SidebarMenuItem key={entry.key}>
                    <SidebarMenuButton
                      asChild
                      isActive={section === entry.key}
                      tooltip={entry.label}
                    >
                      <Link href={href} data-testid={`nav-${entry.key}`}>
                        <Icon aria-hidden="true" />
                        <span>{entry.label}</span>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroup>
        </SidebarContent>
      </AppShellSidebar>

      <AppShellMain>
        <AppShellContent>{children}</AppShellContent>
      </AppShellMain>
    </AppShell>
  );
}

/** The order the sidebar renders, exported so a test asserts the decision. */
export const PANEL_NAVIGATION = NAVIGATION;
