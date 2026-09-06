'use client';

import * as React from 'react';
import { Progress as ProgressPrimitive } from 'radix-ui';

import { cn } from '@/lib/utils';

function Progress({
  className,
  value,
  ...props
}: React.ComponentProps<typeof ProgressPrimitive.Root>) {
  const isIndeterminate = value == null;

  return (
    <ProgressPrimitive.Root
      data-slot="progress"
      className={cn(
        'relative flex h-1 w-full items-center overflow-x-hidden rounded-full bg-muted',
        className,
      )}
      {...props}
    >
      <ProgressPrimitive.Indicator
        data-slot="progress-indicator"
        className={cn(
          'size-full flex-1 bg-primary transition-all',
          isIndeterminate &&
            'animate-[progress-loading_2s_linear_infinite] motion-reduce:animate-pulse',
        )}
        style={{
          transform: isIndeterminate ? 'translateX(0)' : `translateX(-${100 - value}%)`,
        }}
      />
    </ProgressPrimitive.Root>
  );
}

export { Progress };
