'use client';

import * as React from 'react';

import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Icons } from '@/components/ui/icons';
import { cn } from '@/lib/utils';

type NotificationItem = {
  id: string;
  title: React.ReactNode;
  description?: React.ReactNode;
  timestamp?: React.ReactNode;
  read?: boolean;
  avatarSrc?: string;
  avatarAlt?: string;
  avatarFallback?: string;
  href?: string;
};

type NotificationsProps = {
  notifications?: NotificationItem[];
  label?: string;
  emptyLabel?: string;
  viewAllLabel?: string;
  viewAllHref?: string;
  unreadCount?: number;
  onNotificationSelect?: (notification: NotificationItem) => void;
  onViewAll?: () => void;
  disabled?: boolean;
  className?: string;
  contentClassName?: string;
  align?: React.ComponentProps<typeof DropdownMenuContent>['align'];
  side?: React.ComponentProps<typeof DropdownMenuContent>['side'];
};

function Notifications({
  notifications = [],
  label = 'Notificações',
  emptyLabel = 'Nenhuma notificação recente.',
  viewAllLabel = 'Ver todas as notificações',
  viewAllHref = '#notificacoes',
  unreadCount,
  onNotificationSelect,
  onViewAll,
  disabled = false,
  className,
  contentClassName,
  align = 'end',
  side = 'bottom',
}: NotificationsProps) {
  const totalUnread =
    unreadCount ?? notifications.filter((notification) => !notification.read).length;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          disabled={disabled}
          aria-label={totalUnread > 0 ? `${label}: ${totalUnread} não lidas` : label}
          title={label}
          className={cn(
            'relative size-11 rounded-full p-0 hover:bg-app-shell-accent hover:text-app-shell-accent-foreground aria-expanded:bg-app-shell-accent aria-expanded:text-app-shell-accent-foreground',
            className,
          )}
        >
          <Avatar className="size-10">
            <AvatarFallback className="bg-secondary text-secondary-foreground">
              <Icons.notification />
            </AvatarFallback>
          </Avatar>
          {totalUnread > 0 ? (
            <span className="absolute -top-1 -right-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-danger px-1 text-xs font-medium text-danger-foreground">
              {totalUnread > 99 ? '99+' : totalUnread}
            </span>
          ) : null}
        </Button>
      </DropdownMenuTrigger>

      <DropdownMenuContent
        align={align}
        side={side}
        sideOffset={8}
        className={cn(
          'w-96 max-w-[calc(100vw-2rem)] rounded-md p-0 shadow-2xl shadow-primary/30',
          contentClassName,
        )}
      >
        <div className="flex items-center justify-between gap-3 px-4 py-3">
          <div className="text-lg font-medium">{label}</div>
          {totalUnread > 0 ? <Badge variant="secondary">{totalUnread} novas</Badge> : null}
        </div>
        <DropdownMenuSeparator className="m-0" />

        <div className="max-h-96 overflow-y-auto p-1">
          {notifications.length > 0 ? (
            notifications.map((notification) => (
              <DropdownMenuItem
                key={notification.id}
                className="cursor-pointer items-start gap-3 rounded-md p-3"
                onSelect={() => onNotificationSelect?.(notification)}
                asChild={Boolean(notification.href)}
              >
                {notification.href ? (
                  <a href={notification.href}>
                    <NotificationContent notification={notification} />
                  </a>
                ) : (
                  <NotificationContent notification={notification} />
                )}
              </DropdownMenuItem>
            ))
          ) : (
            <div className="px-4 py-8 text-center text-lg font-extralight text-muted-foreground">
              {emptyLabel}
            </div>
          )}
        </div>

        <DropdownMenuSeparator className="m-0" />
        <DropdownMenuItem asChild className="rounded-md p-0">
          <a
            href={viewAllHref}
            className="flex w-full cursor-pointer items-center justify-center gap-2 px-4 py-3 font-medium text-primary"
            onClick={onViewAll}
          >
            {viewAllLabel}
            <Icons.chevronRight />
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function NotificationContent({ notification }: { notification: NotificationItem }) {
  return (
    <>
      <Avatar className="size-10 shrink-0">
        {notification.avatarSrc ? (
          <AvatarImage src={notification.avatarSrc} alt={notification.avatarAlt ?? ''} />
        ) : null}
        <AvatarFallback className="bg-muted text-foreground">
          {notification.avatarFallback ?? <Icons.notification />}
        </AvatarFallback>
      </Avatar>
      <div className="min-w-0 flex-1 space-y-1">
        <div className="flex items-start gap-2">
          <span className="min-w-0 flex-1 text-lg font-medium">{notification.title}</span>
          {!notification.read ? (
            <span className="mt-2 size-2 shrink-0 rounded-full bg-primary" aria-label="Não lida" />
          ) : null}
        </div>
        {notification.description ? (
          <div className="line-clamp-2 text-base font-extralight text-muted-foreground">
            {notification.description}
          </div>
        ) : null}
        {notification.timestamp ? (
          <div className="text-base font-extralight text-muted-foreground">
            {notification.timestamp}
          </div>
        ) : null}
      </div>
    </>
  );
}

export { Notifications, type NotificationItem, type NotificationsProps };
