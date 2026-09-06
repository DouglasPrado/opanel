import { Icons } from '@/components/ui/icons';
import { cn } from '@/lib/utils';

function Spinner({ className, ...props }: React.ComponentProps<'svg'>) {
  return (
    <Icons.loading
      data-slot="spinner"
      role="status"
      aria-label="Loading"
      className={cn('size-[18px] animate-spin', className)}
      {...props}
    />
  );
}

export { Spinner };
