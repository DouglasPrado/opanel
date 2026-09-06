import * as React from 'react';
import { RadioGroup as RadioGroupPrimitive } from 'radix-ui';

import { cn } from '@/lib/utils';

function RadioGroup({
  className,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Root>) {
  return (
    <RadioGroupPrimitive.Root
      data-slot="radio-group"
      className={cn('grid w-full gap-2', className)}
      {...props}
    />
  );
}

function RadioGroupItem({
  className,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Item>) {
  return (
    <RadioGroupPrimitive.Item
      data-slot="radio-group-item"
      className={cn(
        'group/radio-group-item peer relative flex aspect-square size-[18px] shrink-0 rounded-full border border-input outline-none group-has-[:focus-visible]/field-label:ring-0 group-has-[:focus-visible]/field-label:not-data-checked:border-input after:absolute after:-inset-x-3 after:-inset-y-2 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 aria-invalid:aria-checked:border-primary dark:bg-input/30 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 data-checked:border-primary data-checked:bg-primary data-checked:text-primary-foreground group-has-[:focus-visible]/field-label:data-checked:border-primary dark:data-checked:bg-primary',
        className,
      )}
      {...props}
    >
      <RadioGroupPrimitive.Indicator
        data-slot="radio-group-indicator"
        className="flex size-[18px] items-center justify-center"
      >
        <span className="absolute top-1/2 left-1/2 size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary-foreground" />
      </RadioGroupPrimitive.Indicator>
    </RadioGroupPrimitive.Item>
  );
}

function RadioGroupChoice({
  children,
  className,
  description,
  id,
  itemClassName,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Item> & {
  description?: React.ReactNode;
  itemClassName?: string;
}) {
  const generatedId = React.useId();
  const itemId = id ?? generatedId;

  return (
    <label
      data-slot="radio-group-choice"
      htmlFor={itemId}
      className={cn(
        'group/radio-group-choice relative flex min-h-11 cursor-pointer items-start gap-2.5 rounded-xs border border-input bg-transparent px-3 py-2.5 text-start text-lg transition-colors outline-none select-none hover:bg-muted/50 has-[:focus-visible]:border-ring has-[:focus-visible]:ring-3 has-[:focus-visible]:ring-ring/50 has-data-checked:border-primary/40 has-data-checked:bg-muted has-data-disabled:pointer-events-none has-data-disabled:cursor-not-allowed has-data-disabled:opacity-50 dark:bg-input/20 dark:has-data-checked:bg-muted',
        className,
      )}
    >
      <RadioGroupItem id={itemId} className={cn('mt-1', itemClassName)} {...props} />
      <span className="flex min-w-0 flex-1 flex-col gap-0.5 leading-snug">
        <span>{children}</span>
        {description != null && (
          <span className="text-base text-muted-foreground">{description}</span>
        )}
      </span>
    </label>
  );
}

export { RadioGroup, RadioGroupChoice, RadioGroupItem };
