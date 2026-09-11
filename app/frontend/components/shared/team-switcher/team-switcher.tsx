import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Icons } from '@/components/ui/icons';
import { cn } from '@/lib/utils';

export interface TeamOption {
  id: string;
  name: string;
  slug: string;
  /** The actor's role in this Team, shown so switching is an informed choice. */
  role?: string;
}

export interface TeamSwitcherProps {
  teams: TeamOption[];
  currentTeamId?: string | null;
  onSelect?: (team: TeamOption) => void;
  onCreate?: () => void;
  className?: string;
  label?: string;
}

/**
 * The Team the operator is acting in, and the way to change it.
 *
 * ## Reuse Gate
 *
 * No new visual: it composes `dropdown-menu`, `button` and `icons`. It lives in
 * `shared/` rather than in a feature because the app shell needs it and so will
 * every page that has to say which tenant it is showing — which is all of them.
 * The inventory has no team switcher; `select` was considered and rejected,
 * because this is navigation between tenants rather than choosing a value in a
 * form, and the inventory's own "do not use when" for `select` says so.
 *
 * ## Why the current Team is a label and not just a checkmark
 *
 * Acting in the wrong Team is the mistake this control exists to prevent, and it
 * is silent — the pages look the same. So the trigger always states the Team by
 * name, and the menu marks the current one with an icon **and** the word, never
 * with colour alone (AC7).
 */
export function TeamSwitcher({
  teams,
  currentTeamId,
  onSelect,
  onCreate,
  className,
  label = 'Switch team',
}: TeamSwitcherProps) {
  const current = teams.find((team) => team.id === currentTeamId) ?? teams[0];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className={cn('max-w-56 justify-between gap-2', className)}
          aria-label={label}
          data-testid="team-switcher"
        >
          <span className="truncate">{current ? current.name : 'No team'}</span>
          <Icons.chevronDown aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>

      <DropdownMenuContent align="start" className="w-64">
        <DropdownMenuLabel>Teams</DropdownMenuLabel>
        <DropdownMenuSeparator />

        {teams.map((team) => {
          const isCurrent = current?.id === team.id;

          return (
            <DropdownMenuItem
              key={team.id}
              onSelect={() => onSelect?.(team)}
              data-testid={`team-switcher-option-${team.slug}`}
              // Announced, not merely drawn: a screen reader hears which Team is
              // current without relying on the icon.
              aria-current={isCurrent ? 'true' : undefined}
            >
              <span className="flex-1 truncate">{team.name}</span>
              {team.role ? (
                <span className="text-muted-foreground text-xs">{team.role}</span>
              ) : null}
              {isCurrent ? (
                <>
                  <Icons.confirm aria-hidden="true" />
                  <span className="sr-only">(current)</span>
                </>
              ) : null}
            </DropdownMenuItem>
          );
        })}

        {onCreate ? (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={onCreate} data-testid="team-switcher-create">
              <Icons.plus aria-hidden="true" />
              Create a team
            </DropdownMenuItem>
          </>
        ) : null}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
