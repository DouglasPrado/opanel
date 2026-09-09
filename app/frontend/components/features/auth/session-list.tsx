import { useState } from 'react';

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from '@/components/ui/empty';
import { Icons } from '@/components/ui/icons';
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemGroup,
  ItemMedia,
  ItemTitle,
} from '@/components/ui/item';

/** One row of the list, exactly as the server sends it. */
export interface SessionListEntry {
  /** Prefixed identifier, `ses_…` (ADR-0002 §2). */
  id: string;
  /** True for the session making the request. */
  current: boolean;
  /** Derived on the server: unrevoked, inside both lifetimes. */
  active: boolean;
  ipAddress: string | null;
  userAgent: string | null;
  lastSeenAt: string;
  createdAt: string;
  expiresAt: string;
  revokedAt: string | null;
}

interface SessionListProps {
  sessions: SessionListEntry[];
  onRevoke: (id: string) => void;
  /** Set while a revocation is in flight, so the row cannot be submitted twice. */
  revokingId?: string | null;
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ['year', 365 * 24 * 60 * 60],
  ['month', 30 * 24 * 60 * 60],
  ['day', 24 * 60 * 60],
  ['hour', 60 * 60],
  ['minute', 60],
];

/**
 * "3 hours ago" rather than a timestamp: the question the page answers is
 * "which of these is still me", and a raw UTC string makes the reader do the
 * arithmetic. The exact value stays in the `dateTime` attribute.
 */
function relativeTime(value: string): string {
  const then = Date.parse(value);
  if (Number.isNaN(then)) {
    return value;
  }

  const seconds = Math.round((then - Date.now()) / 1000);
  const format = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

  for (const [unit, size] of UNITS) {
    if (Math.abs(seconds) >= size) {
      return format.format(Math.round(seconds / size), unit);
    }
  }

  return format.format(seconds, 'second');
}

/**
 * The user's devices, with the one action the Story allows on them.
 *
 * Reuse Gate (Annex I §6.3): no equivalent exists — `shared/profile` is an
 * account menu, not a device list — and composition alone does not cover it
 * because this carries behaviour: which row is the current session, a relative
 * `lastSeenAt`, a confirmation before an irreversible revocation, and the
 * in-flight disabled state. It composes `ui/item`, `ui/badge`, `ui/button`,
 * `ui/alert-dialog` and `ui/empty`, and introduces no new visual.
 */
export function SessionList({ sessions, onRevoke, revokingId = null }: SessionListProps) {
  const [pending, setPending] = useState<SessionListEntry | null>(null);

  if (sessions.length === 0) {
    return (
      <Empty data-testid="session-list-empty">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <Icons.securityCheck />
          </EmptyMedia>
          <EmptyTitle>No active sessions</EmptyTitle>
          <EmptyDescription>
            Signing in on a device adds it here, and you can end it from this page.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <>
      <ItemGroup>
        {sessions.map((session) => (
          <Item key={session.id} variant="outline" data-testid="session-item">
            <ItemMedia>
              <Icons.account aria-hidden />
            </ItemMedia>

            <ItemContent>
              <ItemTitle>{session.userAgent ?? 'Unknown device'}</ItemTitle>
              <ItemDescription>
                {session.ipAddress ?? 'Unknown address'} · last seen{' '}
                <time data-testid="session-last-seen" dateTime={session.lastSeenAt}>
                  {relativeTime(session.lastSeenAt)}
                </time>
              </ItemDescription>
            </ItemContent>

            <ItemActions>
              {session.current ? <Badge variant="secondary">This device</Badge> : null}
              {!session.active ? <Badge variant="outline">Revoked</Badge> : null}

              {session.active ? (
                <Button
                  variant={session.current ? 'outline' : 'destructive'}
                  size="sm"
                  disabled={revokingId === session.id}
                  onClick={() => setPending(session)}
                >
                  {revokingId === session.id
                    ? 'Revoking…'
                    : session.current
                      ? 'Sign out'
                      : 'Revoke'}
                </Button>
              ) : null}
            </ItemActions>
          </Item>
        ))}
      </ItemGroup>

      <AlertDialog open={pending !== null} onOpenChange={(open) => !open && setPending(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {pending?.current ? 'Sign out of this device?' : 'Revoke this session?'}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {pending?.current
                ? 'You will be signed out and returned to the sign-in page.'
                : 'That device will be signed out on its next request. This cannot be undone.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (pending) {
                  onRevoke(pending.id);
                }
                setPending(null);
              }}
            >
              {pending?.current ? 'Sign out' : 'Revoke'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
