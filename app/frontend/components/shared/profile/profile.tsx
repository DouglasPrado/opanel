'use client';

import * as React from 'react';
import { ChevronsUpDown, LogOut, Settings } from 'lucide-react';

import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

type ProfileProps = {
  name: string;
  email: string;
  avatarSrc?: string;
  avatarAlt?: string;
  fallback?: string;
  settingsLabel?: string;
  logoutLabel?: string;
  onSettings?: () => void;
  onLogout?: () => void;
  disabled?: boolean;
  side?: React.ComponentProps<typeof DropdownMenuContent>['side'];
  align?: React.ComponentProps<typeof DropdownMenuContent>['align'];
  className?: string;
  contentClassName?: string;
};

function getInitials(name: string) {
  const initials = name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0))
    .join('')
    .toUpperCase();

  return initials || '?';
}

function Profile({
  name,
  email,
  avatarSrc,
  avatarAlt = name,
  fallback = getInitials(name),
  settingsLabel = 'Configurações',
  logoutLabel = 'Sair',
  onSettings,
  onLogout,
  disabled = false,
  side = 'right',
  align = 'end',
  className,
  contentClassName,
}: ProfileProps) {
  const renderAvatar = () => (
    <Avatar className="size-10 shrink-0 rounded-md after:rounded-md">
      {avatarSrc ? <AvatarImage src={avatarSrc} alt={avatarAlt} className="rounded-md" /> : null}
      <AvatarFallback className="rounded-md text-base font-medium">{fallback}</AvatarFallback>
    </Avatar>
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          disabled={disabled}
          aria-label={`Abrir menu de ${name}`}
          title={`${name} — ${email}`}
          className={cn(
            'h-14 w-full min-w-0 justify-start gap-3 overflow-hidden rounded-md p-2 text-left transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground aria-expanded:bg-sidebar-accent aria-expanded:text-sidebar-accent-foreground data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground dark:hover:bg-sidebar-accent group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:justify-center group-data-[collapsible=icon]:p-0!',
            className,
          )}
        >
          {renderAvatar()}
          <div className="grid min-w-0 flex-1 leading-tight group-data-[collapsible=icon]:hidden">
            <span className="truncate text-base font-medium">{name}</span>
            <span className="truncate text-base font-normal text-inherit opacity-70">{email}</span>
          </div>
          <ChevronsUpDown
            aria-hidden="true"
            className="ml-auto group-data-[collapsible=icon]:hidden"
          />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        side={side}
        align={align}
        sideOffset={8}
        className={cn('min-w-64 rounded-md', contentClassName)}
      >
        <DropdownMenuLabel className="p-2 font-normal">
          <div className="flex items-center gap-3">
            {renderAvatar()}
            <div className="grid min-w-0 flex-1 leading-tight">
              <span className="truncate text-base font-medium">{name}</span>
              <span className="truncate text-base font-normal text-popover-foreground/70">
                {email}
              </span>
            </div>
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuGroup>
          <DropdownMenuItem
            className="cursor-pointer rounded-md px-2 py-2"
            onSelect={() => onSettings?.()}
          >
            <Settings aria-hidden="true" />
            {settingsLabel}
          </DropdownMenuItem>
        </DropdownMenuGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          variant="destructive"
          className="cursor-pointer rounded-md px-2 py-2"
          onSelect={() => onLogout?.()}
        >
          <LogOut aria-hidden="true" />
          {logoutLabel}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export { Profile, type ProfileProps };
