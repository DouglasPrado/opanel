import * as React from 'react';

import { SkeletonButton } from '@/components/ui/button';
import { SkeletonInput } from '@/components/ui/input';
import { SkeletonPagination } from '@/components/ui/pagination';
import { Skeleton } from '@/components/ui/skeleton';
import { createComponentSkeleton } from '@/components/ui/skeleton/skeleton-layout';
import { cn } from '@/lib/utils';

const SkeletonTable = createComponentSkeleton('SkeletonTable', 'table');

function SkeletonDataTable({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="skeleton-data-table"
      aria-hidden="true"
      className={cn('w-full space-y-4', className)}
      {...props}
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
        <SkeletonInput className="sm:max-w-md" />
        <SkeletonButton className="sm:ml-auto sm:w-36" />
      </div>
      <SkeletonTable />
      <div className="flex flex-col gap-4 px-2 sm:flex-row sm:items-center sm:justify-between">
        <Skeleton className="h-5 w-52 rounded-md" />
        <SkeletonPagination className="sm:w-auto" />
      </div>
    </div>
  );
}

export { SkeletonDataTable, SkeletonTable };
