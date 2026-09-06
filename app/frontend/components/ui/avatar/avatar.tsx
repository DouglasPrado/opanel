import * as React from 'react';
import { Avatar as AvatarPrimitive } from 'radix-ui';

import { cn } from '@/lib/utils';

function Avatar({
  className,
  size = 'default',
  ...props
}: React.ComponentProps<typeof AvatarPrimitive.Root> & {
  size?: 'default' | 'sm' | 'lg';
}) {
  return (
    <AvatarPrimitive.Root
      data-slot="avatar"
      data-size={size}
      className={cn(
        'group/avatar relative flex size-8 shrink-0 rounded-full select-none after:absolute after:inset-0 after:rounded-full after:border after:border-border after:mix-blend-darken data-[size=lg]:size-10 data-[size=sm]:size-6 dark:after:mix-blend-lighten',
        className,
      )}
      {...props}
    />
  );
}

function AvatarImage({ className, ...props }: React.ComponentProps<typeof AvatarPrimitive.Image>) {
  return (
    <AvatarPrimitive.Image
      data-slot="avatar-image"
      className={cn('aspect-square size-full rounded-full object-cover', className)}
      {...props}
    />
  );
}

function AvatarFallback({
  className,
  ...props
}: React.ComponentProps<typeof AvatarPrimitive.Fallback>) {
  return (
    <AvatarPrimitive.Fallback
      data-slot="avatar-fallback"
      className={cn(
        'flex size-full items-center justify-center rounded-full bg-muted text-base text-muted-foreground group-data-[size=sm]/avatar:text-xs',
        className,
      )}
      {...props}
    />
  );
}

/*
 * Os quatro cantos como mapa, e não como classes soltas no consumidor.
 *
 * `absolute right-0 bottom-0` no base obriga quem quer o badge à esquerda a
 * escrever `right-auto left-0` — duas classes de eixos diferentes que o
 * tailwind-merge não resolve entre si, então esquecer o `right-auto` posiciona
 * o badge nos dois cantos ao mesmo tempo. Escolher o par aqui tira a pegadinha.
 */
const AVATAR_BADGE_POSITION = {
  'bottom-right': 'right-0 bottom-0',
  'bottom-left': 'bottom-0 left-0',
  'top-right': 'top-0 right-0',
  'top-left': 'top-0 left-0',
} as const;

/*
 * Presença em tokens semânticos, não na paleta bruta do Tailwind.
 *
 * `bg-green-500` ignora a marca e não acompanha o tema: o verde vem de
 * `--brand-success`, e o amarelo de "ausente" é a própria secundária.
 */
const AVATAR_BADGE_STATUS = {
  online: 'bg-success text-success-foreground',
  away: 'bg-secondary text-secondary-foreground',
  busy: 'bg-danger text-danger-foreground',
  offline: 'bg-disabled text-background',
} as const;

type AvatarBadgeProps = React.ComponentProps<'span'> & {
  position?: keyof typeof AVATAR_BADGE_POSITION;
  status?: keyof typeof AVATAR_BADGE_STATUS;
};

function AvatarBadge({ className, position = 'bottom-right', status, ...props }: AvatarBadgeProps) {
  return (
    <span
      data-slot="avatar-badge"
      data-position={position}
      data-status={status}
      className={cn(
        'absolute z-10 inline-flex items-center justify-center rounded-full bg-primary text-primary-foreground bg-blend-color ring-2 ring-background select-none',
        AVATAR_BADGE_POSITION[position],
        status === undefined ? undefined : AVATAR_BADGE_STATUS[status],
        'group-data-[size=sm]/avatar:size-2 group-data-[size=sm]/avatar:[&>svg]:hidden',
        'group-data-[size=default]/avatar:size-2.5 group-data-[size=default]/avatar:[&>svg]:size-2',
        'group-data-[size=lg]/avatar:size-3 group-data-[size=lg]/avatar:[&>svg]:size-2',
        className,
      )}
      {...props}
    />
  );
}

function AvatarGroup({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="avatar-group"
      className={cn(
        'group/avatar-group flex -space-x-2 *:data-[slot=avatar]:ring-2 *:data-[slot=avatar]:ring-background',
        className,
      )}
      {...props}
    />
  );
}

function AvatarGroupCount({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="avatar-group-count"
      className={cn(
        'relative flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-base text-muted-foreground ring-2 ring-background group-has-data-[size=lg]/avatar-group:size-10 group-has-data-[size=sm]/avatar-group:size-6 [&>svg]:size-[18px] group-has-data-[size=lg]/avatar-group:[&>svg]:size-5 group-has-data-[size=sm]/avatar-group:[&>svg]:size-3',
        className,
      )}
      {...props}
    />
  );
}

export {
  Avatar,
  AvatarImage,
  AvatarFallback,
  AvatarGroup,
  AvatarGroupCount,
  AvatarBadge,
  type AvatarBadgeProps,
};
