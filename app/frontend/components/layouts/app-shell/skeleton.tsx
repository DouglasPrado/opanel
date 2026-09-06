import * as React from 'react';

import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

function SkeletonAppShell({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="skeleton-app-shell"
      aria-hidden="true"
      className={cn('relative flex h-svh w-full overflow-hidden bg-app-shell pt-16', className)}
      {...props}
    >
      <div className="absolute inset-x-0 top-0 flex h-16 items-center gap-3 px-[19px]">
        <Skeleton className="size-7 bg-app-shell-accent" />
        <Skeleton className="size-10 bg-primary/40" />
        <Skeleton className="h-5 w-32 bg-app-shell-accent" />
      </div>
      <div className="hidden w-72 shrink-0 space-y-3 p-3 md:block">
        {[1, 2, 3, 4].map((item) => (
          <Skeleton key={item} className="h-12 w-full bg-app-shell-accent" />
        ))}
      </div>
      <div className="flex flex-1 flex-col gap-6 rounded-t-xl bg-card p-6 shadow-2xl shadow-primary/20">
        <Skeleton className="h-8 w-52" />
        <Skeleton className="h-5 w-80 max-w-full" />
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {[1, 2, 3, 4].map((item) => (
            <Skeleton key={item} className="h-32 w-full rounded-md" />
          ))}
        </div>
        <Skeleton className="min-h-64 w-full flex-1 rounded-md" />
      </div>
    </div>
  );
}

export { SkeletonAppShell };
