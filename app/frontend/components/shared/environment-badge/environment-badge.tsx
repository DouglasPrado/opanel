import { Badge } from '@/components/ui/badge';
import { Icons } from '@/components/ui/icons';
import { cn } from '@/lib/utils';

export type EnvironmentKind = 'PRODUCTION' | 'HOMOLOGATION' | 'DEVELOPMENT' | 'PREVIEW' | 'CUSTOM';

export interface EnvironmentBadgeProps {
  kind: EnvironmentKind;
  className?: string;
}

/**
 * Which Environment the page is showing, stated persistently.
 *
 * AC5 asks for `PRODUCTION` to be visually persistent, and the reason is the one
 * doc 10 gives throughout: the expensive mistakes are the ones made in the wrong
 * Environment, and they are silent — production and staging render identically.
 * So this is never hidden behind a hover or collapsed away on a narrow screen.
 *
 * ## Reuse Gate
 *
 * Composes `badge` and `icons`; adds no visual of its own. It is in `shared/`
 * because M01-11 onward puts it on Environment, Service and deployment pages
 * alike, and the whole value is that it looks the same in all of them.
 *
 * ## Not colour alone
 *
 * AC7. `PRODUCTION` carries an icon and the word, so it survives a colour-blind
 * reader and a greyscale screenshot pasted into an incident.
 */
const KIND_LABEL: Record<EnvironmentKind, string> = {
  PRODUCTION: 'Production',
  HOMOLOGATION: 'Homologation',
  DEVELOPMENT: 'Development',
  PREVIEW: 'Preview',
  CUSTOM: 'Custom',
};

export function EnvironmentBadge({ kind, className }: EnvironmentBadgeProps) {
  const isProduction = kind === 'PRODUCTION';

  return (
    <Badge
      variant={isProduction ? 'destructive' : 'secondary'}
      className={cn('gap-1', className)}
      data-testid="environment-badge"
      data-environment={kind}
    >
      {isProduction ? <Icons.alert aria-hidden="true" /> : null}
      {KIND_LABEL[kind]}
    </Badge>
  );
}
