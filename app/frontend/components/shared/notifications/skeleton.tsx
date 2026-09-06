import * as React from 'react';

import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

function SkeletonNotifications({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="skeleton-notifications"
      aria-hidden="true"
      className={cn('relative size-11', className)}
      {...props}
    >
      <Skeleton className="size-10 rounded-full" />
      <Skeleton className="absolute -top-1 -right-1 size-5 rounded-full" />
    </div>
  );
}

export { SkeletonNotifications };
