import * as React from 'react';

import { cn } from '@/lib/utils';

import { Skeleton } from './skeleton';

type SkeletonLayoutVariant =
  | 'avatar'
  | 'badge'
  | 'breadcrumb'
  | 'button'
  | 'button-group'
  | 'chart'
  | 'control'
  | 'field'
  | 'form'
  | 'icon'
  | 'list'
  | 'media'
  | 'message'
  | 'navigation'
  | 'otp'
  | 'overlay'
  | 'pagination'
  | 'panel'
  | 'profile'
  | 'progress'
  | 'separator'
  | 'slider'
  | 'spinner'
  | 'table'
  | 'tabs'
  | 'textarea'
  | 'text'
  | 'title'
  | 'upload';

type SkeletonLayoutProps = React.ComponentProps<'div'> & {
  variant: SkeletonLayoutVariant;
};

const field = (
  <>
    <Skeleton className="h-5 w-28 rounded-md" />
    <Skeleton className="h-14 w-full rounded-md" />
  </>
);

function SkeletonLayout({ variant, className, ...props }: SkeletonLayoutProps) {
  let content: React.ReactNode;

  switch (variant) {
    case 'avatar':
      content = <Skeleton className="size-10 rounded-full" />;
      break;
    case 'badge':
      content = <Skeleton className="h-7 w-24 rounded-md" />;
      break;
    case 'breadcrumb':
      content = (
        <div className="flex items-center gap-2">
          <Skeleton className="h-5 w-20 rounded-md" />
          <Skeleton className="size-3 rounded-md" />
          <Skeleton className="h-5 w-28 rounded-md" />
          <Skeleton className="size-3 rounded-md" />
          <Skeleton className="h-5 w-24 rounded-md" />
        </div>
      );
      break;
    case 'button':
      content = <Skeleton className="h-14 w-36 rounded-md" />;
      break;
    case 'button-group':
      content = (
        <div className="flex">
          <Skeleton className="h-14 w-28 rounded-l-md rounded-r-none" />
          <Skeleton className="h-14 w-28 rounded-none" />
          <Skeleton className="h-14 w-28 rounded-r-md rounded-l-none" />
        </div>
      );
      break;
    case 'chart':
      content = (
        <div className="flex h-52 items-end gap-3 rounded-md border p-4">
          {[45, 70, 55, 88, 64].map((height) => (
            <Skeleton key={height} className="flex-1 rounded-md" style={{ height: `${height}%` }} />
          ))}
        </div>
      );
      break;
    case 'control':
      content = (
        <div className="flex items-center gap-3">
          <Skeleton className="size-[18px] shrink-0 rounded-md" />
          <Skeleton className="h-5 w-36 rounded-md" />
        </div>
      );
      break;
    case 'field':
      content = field;
      break;
    case 'form':
      content = (
        <>
          {field}
          {field}
          <Skeleton className="h-14 w-full rounded-md" />
        </>
      );
      break;
    case 'icon':
      content = <Skeleton className="size-[18px] rounded-md" />;
      break;
    case 'list':
      content = (
        <div className="space-y-0 rounded-md border p-2">
          {['w-4/5', 'w-3/5', 'w-2/3'].map((width) => (
            <div key={width} className="flex h-12 items-center gap-3 px-2">
              <Skeleton className="size-[18px] shrink-0 rounded-md" />
              <Skeleton className={cn('h-5 rounded-md', width)} />
            </div>
          ))}
        </div>
      );
      break;
    case 'media':
      content = <Skeleton className="aspect-video w-full rounded-md" />;
      break;
    case 'message':
      content = (
        <div className="flex items-end gap-3">
          <Skeleton className="size-9 shrink-0 rounded-full" />
          <div className="w-3/4 space-y-2 rounded-md border p-3">
            <Skeleton className="h-5 w-2/5 rounded-md" />
            <Skeleton className="h-5 w-full rounded-md" />
          </div>
        </div>
      );
      break;
    case 'navigation':
      content = (
        <div className="w-72 space-y-2 rounded-md border p-3">
          <Skeleton className="mb-4 h-10 w-3/5 rounded-md" />
          {[1, 2, 3, 4].map((item) => (
            <Skeleton key={item} className="h-12 w-full rounded-md" />
          ))}
        </div>
      );
      break;
    case 'otp':
      content = (
        <div className="flex w-full gap-2">
          {[1, 2, 3, 4, 5, 6].map((item) => (
            <Skeleton key={item} className="h-14 min-w-0 flex-1 rounded-md" />
          ))}
        </div>
      );
      break;
    case 'overlay':
      content = (
        <div className="w-full max-w-sm space-y-4 rounded-md border p-5 shadow-2xl shadow-(color:--shadow-surface)">
          <Skeleton className="h-6 w-2/5 rounded-md" />
          <Skeleton className="h-5 w-full rounded-md" />
          <Skeleton className="h-5 w-4/5 rounded-md" />
          <div className="flex justify-end gap-2 pt-2">
            <Skeleton className="h-12 w-28 rounded-md" />
            <Skeleton className="h-12 w-28 rounded-md" />
          </div>
        </div>
      );
      break;
    case 'pagination':
      content = (
        <div className="flex gap-2">
          {[16, 10, 10, 10, 16].map((width, index) => (
            <Skeleton
              key={`${width}-${index}`}
              className="h-10 rounded-md"
              style={{ width: `${width * 4}px` }}
            />
          ))}
        </div>
      );
      break;
    case 'panel':
      content = (
        <div className="space-y-4 rounded-md border p-5">
          <Skeleton className="h-6 w-2/5 rounded-md" />
          <Skeleton className="h-5 w-full rounded-md" />
          <Skeleton className="h-5 w-4/5 rounded-md" />
        </div>
      );
      break;
    case 'profile':
      content = (
        <div className="flex h-14 items-center gap-3 rounded-md p-2">
          <Skeleton className="size-10 shrink-0 rounded-md" />
          <div className="min-w-0 flex-1 space-y-2">
            <Skeleton className="h-5 w-2/5 rounded-md" />
            <Skeleton className="h-4 w-3/5 rounded-md" />
          </div>
          <Skeleton className="size-[18px] rounded-md" />
        </div>
      );
      break;
    case 'progress':
      content = <Skeleton className="h-3 w-full rounded-full" />;
      break;
    case 'separator':
      content = <Skeleton className="h-px w-full rounded-none" />;
      break;
    case 'slider':
      content = (
        <div className="relative flex h-8 items-center">
          <Skeleton className="h-2 w-full rounded-full" />
          <Skeleton className="absolute left-1/2 size-[18px] -translate-x-1/2 rounded-full" />
        </div>
      );
      break;
    case 'spinner':
      content = <Skeleton className="size-6 rounded-full" />;
      break;
    case 'table':
      content = (
        <div className="overflow-hidden rounded-md border">
          {[1, 2, 3, 4].map((row) => (
            <div key={row} className="grid grid-cols-3 gap-4 border-b p-3 last:border-b-0">
              <Skeleton className="h-5 rounded-md" />
              <Skeleton className="h-5 rounded-md" />
              <Skeleton className="h-5 rounded-md" />
            </div>
          ))}
        </div>
      );
      break;
    case 'tabs':
      content = (
        <>
          <div className="flex gap-2 rounded-md bg-muted p-1">
            <Skeleton className="h-10 flex-1 rounded-md" />
            <Skeleton className="h-10 flex-1 rounded-md" />
            <Skeleton className="h-10 flex-1 rounded-md" />
          </div>
          <Skeleton className="h-32 w-full rounded-md" />
        </>
      );
      break;
    case 'textarea':
      content = (
        <>
          <Skeleton className="h-5 w-28 rounded-md" />
          <Skeleton className="h-32 w-full rounded-md" />
        </>
      );
      break;
    case 'text':
      content = <Skeleton className="h-5 w-36 rounded-md" />;
      break;
    case 'title':
      content = (
        <>
          <Skeleton className="h-8 w-1/2 rounded-md" />
          <Skeleton className="h-5 w-3/4 rounded-md" />
        </>
      );
      break;
    case 'upload':
      content = (
        <div className="flex h-40 flex-col items-center justify-center gap-3 rounded-md border border-dashed">
          <Skeleton className="size-10 rounded-md" />
          <Skeleton className="h-5 w-1/2 rounded-md" />
          <Skeleton className="h-4 w-1/3 rounded-md" />
        </div>
      );
      break;
  }

  return (
    <div
      data-slot="component-skeleton"
      aria-hidden="true"
      className={cn('w-full space-y-3', className)}
      {...props}
    >
      {content}
    </div>
  );
}

function createComponentSkeleton(displayName: string, variant: SkeletonLayoutVariant) {
  function ComponentSkeleton({ className, ...props }: React.ComponentProps<'div'>) {
    return <SkeletonLayout variant={variant} className={className} {...props} />;
  }

  ComponentSkeleton.displayName = displayName;
  return ComponentSkeleton;
}

export {
  SkeletonLayout,
  createComponentSkeleton,
  type SkeletonLayoutProps,
  type SkeletonLayoutVariant,
};
