import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { motion, type HTMLMotionProps } from 'framer-motion';

import { cn } from '@/lib/utils';

const titleVariants = cva('font-heading font-semibold tracking-tight text-balance text-title', {
  variants: {
    size: {
      sm: 'text-2xl',
      default: 'text-4xl',
      lg: 'text-5xl',
      xl: 'text-6xl',
    },
  },
  defaultVariants: {
    size: 'default',
  },
});

const subtitleVariants = cva('text-subtitle', {
  variants: {
    size: {
      sm: 'text-base',
      default: 'text-lg',
      lg: 'text-xl',
      xl: 'text-2xl',
    },
  },
  defaultVariants: {
    size: 'default',
  },
});

function Title({
  className,
  title,
  subtitle,
  icon,
  as: Heading = 'h2',
  size = 'default',
  animated = true,
  ...props
}: Omit<HTMLMotionProps<'div'>, 'title'> &
  VariantProps<typeof titleVariants> & {
    title: React.ReactNode;
    subtitle?: React.ReactNode;
    icon?: React.ReactNode;
    as?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6';
    animated?: boolean;
  }) {
  return (
    <motion.div
      data-slot="title"
      data-size={size}
      className={cn('flex flex-col gap-1', className)}
      initial={animated ? { opacity: 0, x: -16 } : false}
      animate={animated ? { opacity: 1, x: 0 } : undefined}
      transition={{ duration: 0.4, ease: 'easeOut' }}
      {...props}
    >
      <Heading
        data-slot="title-heading"
        className={cn(titleVariants({ size }), icon != null && 'flex items-center gap-2')}
      >
        {icon != null && (
          <span
            data-slot="title-icon"
            className="shrink-0 [&_svg]:size-[1em] [&_svg]:shrink-0"
            aria-hidden="true"
          >
            {icon}
          </span>
        )}
        {title}
      </Heading>
      {subtitle != null && (
        <p data-slot="title-subtitle" className={cn(subtitleVariants({ size }))}>
          {subtitle}
        </p>
      )}
    </motion.div>
  );
}

export { Title, titleVariants, subtitleVariants };
