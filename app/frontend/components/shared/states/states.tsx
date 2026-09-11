import type { ReactNode } from 'react';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from '@/components/ui/empty';
import { Icons } from '@/components/ui/icons';
import { Marker, MarkerContent, MarkerIcon } from '@/components/ui/marker';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

/**
 * The universal states of doc 10 §25, as components rather than as a pattern
 * everybody re-types.
 *
 * M00-08 proved these states *can* be built from the imported library; every
 * example there assembles one by hand inside a test. That is fine as proof and
 * poor as practice: a page whose author forgets the `role="alert"`, or spells the
 * test id differently, ships a state the journey tests cannot find and a screen
 * reader does not announce. These components carry the contract in
 * `spec/frontend/support/universal-states.ts` — the same test ids and roles the
 * E2E journeys assert against — so a page gets it by composing rather than by
 * remembering.
 *
 * ## Reuse Gate
 *
 * Nothing here is a new visual. Each one composes primitives already in the
 * inventory — `alert`, `empty`, `skeleton`, `marker`, `button`, `icons` — and
 * lives in `shared/` because every feature Story from M01-22 on needs all six.
 * A new *primitive* would have been the wrong answer; so would copying six
 * near-identical blocks into each page.
 *
 * ## Colour is never the signal
 *
 * AC7: every state carries an icon and a label as well as its colour. That is
 * not decoration — a status distinguishable only by hue is invisible to a
 * colour-blind operator and to a black-and-white screenshot in an incident
 * report.
 */

interface StateProps {
  className?: string;
}

/**
 * Loading. A skeleton of the structure that is coming, not a spinner over the
 * whole page: the shape tells the reader what to expect, and the page does not
 * jump when the data lands.
 */
export function LoadingState({
  label,
  lines = 3,
  className,
}: StateProps & { label: string; lines?: number }) {
  return (
    <div
      data-testid="state-loading"
      role="status"
      aria-label={label}
      aria-live="polite"
      className={cn('flex w-full flex-col gap-3', className)}
    >
      {Array.from({ length: lines }, (_, index) => (
        <Skeleton key={index} className="h-12 w-full" />
      ))}
      {/* Announced, never shown: the skeleton is the visual, the text is for
          assistive technology. */}
      <span className="sr-only">{label}</span>
    </div>
  );
}

/**
 * Empty. Says what the collection is *for* and offers the action that fills it —
 * an empty state that only says "nothing here" wastes the one moment the user is
 * looking for guidance.
 */
export function EmptyState({
  title,
  description,
  action,
  className,
}: StateProps & { title: string; description: string; action?: ReactNode }) {
  return (
    <div data-testid="state-empty" className={className}>
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <Icons.folderOpen aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>{title}</EmptyTitle>
          <EmptyDescription>{description}</EmptyDescription>
        </EmptyHeader>
        {action ? <EmptyContent>{action}</EmptyContent> : null}
      </Empty>
    </div>
  );
}

/**
 * No permission. Explains the restriction and names nothing behind it —
 * "you need the ADMIN role" is help; "you cannot see Team Acme's production
 * cluster" is a disclosure (doc 10 §25, Annex C §7.3).
 */
export function NoPermissionState({
  title = 'You do not have access to this',
  description,
  className,
}: StateProps & { title?: string; description: string }) {
  return (
    <div data-testid="state-no-permission" className={className}>
      <Alert variant="destructive" role="alert">
        <Icons.securityCheck aria-hidden="true" />
        <AlertTitle>{withoutInternalDetail(title, 'You do not have access to this')}</AlertTitle>
        <AlertDescription>
          {withoutInternalDetail(description, 'Ask an administrator of this team for access.')}
        </AlertDescription>
      </Alert>
    </div>
  );
}

/**
 * Patterns that must never reach a user: a stack frame, a SQL statement, an
 * internal path, an exception class name. Annex C §17.1 forbids all four in a
 * response, and doc 09 §28's envelope is `code`, `message`, `requestId` —
 * nothing else.
 */
const OPAQUE_MESSAGE = 'Something went wrong on our side. Quote the request id below.';

const INTERNAL_DETAIL = new RegExp(
  [
    // SQL.
    '\\bSELECT\\b|\\bINSERT\\b|\\bUPDATE\\b|\\bDELETE\\s+FROM\\b',
    // A stack frame or a source location.
    '\\.rb:\\d+|\\bat\\s+/|backtrace',
    // Any absolute path, not a list of two. `/var/run/docker.sock` passed the
    // earlier `/app/|/usr/` pair, and naming directories one at a time is a list
    // that is always one entry behind the thing that leaks.
    '(^|[\\s(\'"])/(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+',
    // A URI with credentials in it. This one is not a hint about internals, it is
    // the credential — `postgres://user:pw@db.internal/opanel` carried no SQL and
    // no path and rendered verbatim.
    '[a-z][a-z0-9+.-]*://[^\\s/@]*:[^\\s/@]*@',
    // An exception class: any CamelCase name ending in Error/Exception, plus the
    // namespaced form. Listing three by name missed `RuntimeError`.
    '\\b[A-Z][A-Za-z0-9]*(?:Error|Exception)\\b|\\b[A-Z][A-Za-z0-9]*::[A-Z][A-Za-z0-9]*',
  ].join('|'),
  'i',
);

/**
 * Applies the refusal to any text a state is about to show.
 *
 * Every state that renders caller-supplied prose goes through this, not only the
 * error one: review pointed out that `title` was unfiltered, and that the
 * no-permission screen — which the Story's Security Requirements name explicitly
 * — was not filtered at all.
 */
function withoutInternalDetail(text: string, fallback = OPAQUE_MESSAGE) {
  return INTERNAL_DETAIL.test(text) ? fallback : text;
}

/**
 * Error. Carries the `requestId` so support can find the same request in the
 * server log, and nothing else — no stack trace, no SQL, no internal path
 * (AC4, doc 09 §28).
 *
 * The component **refuses** a description that carries internal detail rather
 * than trusting its caller. The first version simply rendered whatever it was
 * given, and the test that claimed to prove AC4 only ever fed it a clean string —
 * review demonstrated the failure by passing a real `ActiveRecord` message with a
 * file path and watching it print verbatim while the suite stayed green.
 *
 * Refusing here is the right layer: this is the last thing between an error and a
 * screen, and a rule enforced where the risk lands does not depend on every future
 * caller remembering it.
 */
export function ErrorState({
  title = 'Something went wrong',
  description,
  requestId,
  onRetry,
  className,
}: StateProps & {
  title?: string;
  description: string;
  requestId?: string | null;
  onRetry?: () => void;
}) {
  const safeDescription = withoutInternalDetail(description);
  const safeTitle = withoutInternalDetail(title, 'Something went wrong');

  return (
    <div data-testid="state-error" className={className}>
      <Alert variant="destructive" role="alert">
        <Icons.alertCircle aria-hidden="true" />
        <AlertTitle>{safeTitle}</AlertTitle>
        <AlertDescription>
          <p>{safeDescription}</p>
          {requestId ? (
            <p className="mt-2 font-mono text-xs" data-testid="state-error-request-id">
              Request ID: {requestId}
            </p>
          ) : null}
          {onRetry ? (
            <Button variant="outline" size="sm" className="mt-3" onClick={onRetry}>
              Try again
            </Button>
          ) : null}
        </AlertDescription>
      </Alert>
    </div>
  );
}

/**
 * Offline. The Control Plane is unreachable: the last reading stays on screen
 * with its timestamp, and mutations are blocked rather than silently failing.
 * Hiding the data would throw away the only information the operator still has.
 */
export function OfflineState({
  lastSeenAt,
  description = 'The Control Plane is unreachable. What you see is the last reading; changes are paused until it returns.',
  className,
}: StateProps & { lastSeenAt?: string | null; description?: string }) {
  return (
    <div data-testid="state-offline" className={className}>
      <Alert variant="destructive" role="alert">
        <Icons.alert aria-hidden="true" />
        <AlertTitle>Control Plane unreachable</AlertTitle>
        <AlertDescription>
          <p>{withoutInternalDetail(description, 'The Control Plane is unreachable.')}</p>
          {lastSeenAt ? <p className="mt-1 text-xs">Last reading: {lastSeenAt}</p> : null}
        </AlertDescription>
      </Alert>
    </div>
  );
}

/**
 * Stale. The data is real but old. doc 10 §25 is explicit that the interface
 * must never claim Healthy from an observation it has not refreshed — so the
 * age is shown next to the value rather than left to be assumed.
 */
export function StaleState({ observedAt, className }: StateProps & { observedAt: string }) {
  return (
    <span data-testid="state-stale" className={className}>
      <Marker variant="border">
        <MarkerIcon>
          <Icons.calendar aria-hidden="true" />
        </MarkerIcon>
        <MarkerContent>Last observed {observedAt}</MarkerContent>
      </Marker>
    </span>
  );
}
