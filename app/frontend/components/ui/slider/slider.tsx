'use client';

import * as React from 'react';
import { Slider as SliderPrimitive } from 'radix-ui';

import { cn } from '@/lib/utils';

function Slider({
  className,
  defaultValue,
  initialValue,
  onValueChange,
  orientation = 'horizontal',
  showValue = true,
  value,
  min = 0,
  max = 100,
  formatValue = (currentValue) => currentValue.toLocaleString('pt-BR'),
  ...props
}: Omit<React.ComponentProps<typeof SliderPrimitive.Root>, 'defaultValue'> & {
  defaultValue?: number[];
  formatValue?: (value: number) => React.ReactNode;
  initialValue?: number | number[];
  showValue?: boolean;
}) {
  const resolvedDefaultValue = React.useMemo(() => {
    if (Array.isArray(initialValue)) return initialValue;
    if (typeof initialValue === 'number') return [initialValue];
    if (Array.isArray(defaultValue)) return defaultValue;
    return [min];
  }, [defaultValue, initialValue, min]);
  const [internalValues, setInternalValues] = React.useState(resolvedDefaultValue);
  const currentValues = Array.isArray(value) ? value : internalValues;

  React.useEffect(() => {
    if (value == null) setInternalValues(resolvedDefaultValue);
  }, [resolvedDefaultValue, value]);

  function handleValueChange(nextValues: number[]) {
    setInternalValues(nextValues);
    onValueChange?.(nextValues);
  }

  return (
    <div
      data-slot="slider-wrapper"
      data-orientation={orientation}
      className={cn(
        'w-full data-[orientation=vertical]:flex data-[orientation=vertical]:h-full data-[orientation=vertical]:w-fit data-[orientation=vertical]:gap-3',
        className,
      )}
    >
      <SliderPrimitive.Root
        data-slot="slider"
        defaultValue={value == null ? resolvedDefaultValue : undefined}
        value={value}
        min={min}
        max={max}
        orientation={orientation}
        className="relative flex w-full touch-none items-center select-none data-disabled:opacity-50 data-vertical:h-full data-vertical:min-h-40 data-vertical:w-auto data-vertical:flex-col"
        onValueChange={handleValueChange}
        {...props}
      >
        <SliderPrimitive.Track
          data-slot="slider-track"
          className="relative grow overflow-hidden rounded-full bg-muted data-horizontal:h-1.5 data-horizontal:w-full data-vertical:h-full data-vertical:w-1.5"
        >
          <SliderPrimitive.Range
            data-slot="slider-range"
            className="absolute bg-primary select-none data-horizontal:h-full data-vertical:w-full"
          />
        </SliderPrimitive.Track>
        {Array.from({ length: currentValues.length }, (_, index) => (
          <SliderPrimitive.Thumb
            data-slot="slider-thumb"
            key={index}
            className="relative block size-[18px] shrink-0 rounded-full border border-ring bg-white ring-ring/50 transition-[color,box-shadow] select-none after:absolute after:-inset-2 hover:ring-3 focus-visible:ring-3 focus-visible:outline-hidden active:ring-3 disabled:pointer-events-none disabled:opacity-50"
          />
        ))}
      </SliderPrimitive.Root>
      {showValue && (
        <div
          data-slot="slider-values"
          className="mt-2 grid grid-cols-3 items-center text-base text-muted-foreground data-[orientation=vertical]:mt-0 data-[orientation=vertical]:flex data-[orientation=vertical]:flex-col data-[orientation=vertical]:justify-between"
          data-orientation={orientation}
        >
          <span>{formatValue(min)}</span>
          <output className="text-center font-medium text-foreground" aria-live="polite">
            {currentValues.map(formatValue).map((item, index) => (
              <React.Fragment key={index}>
                {index > 0 && ' – '}
                {item}
              </React.Fragment>
            ))}
          </output>
          <span className="text-right">{formatValue(max)}</span>
        </div>
      )}
    </div>
  );
}

export { Slider };
