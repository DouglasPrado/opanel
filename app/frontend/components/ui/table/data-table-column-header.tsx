import type { CellData, Column, RowData } from '@tanstack/react-table';

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Icons } from '@/components/ui/icons';
import { cn } from '@/lib/utils';

import type { DataTableFeatures } from './data-table-features';

type DataTableColumnHeaderProps<TData extends RowData, TValue extends CellData = CellData> = {
  column: Column<DataTableFeatures, TData, TValue>;
  title: string;
  className?: string;
};

function DataTableColumnHeader<TData extends RowData, TValue extends CellData = CellData>({
  column,
  title,
  className,
}: DataTableColumnHeaderProps<TData, TValue>) {
  if (!column.getCanSort()) {
    return <span className={cn('text-lg font-medium', className)}>{title}</span>;
  }

  const sortDirection = column.getIsSorted();

  return (
    <div className={cn('flex items-center gap-2', className)}>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            type="button"
            variant="ghost"
            className="-ml-4 px-4 py-2"
            aria-label={`Ordenar coluna ${title}`}
          >
            {title}
            {sortDirection === 'asc' ? (
              <Icons.chevronUp aria-hidden="true" />
            ) : sortDirection === 'desc' ? (
              <Icons.chevronDown aria-hidden="true" />
            ) : (
              <Icons.arrowsVertical aria-hidden="true" />
            )}
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="min-w-48">
          <DropdownMenuItem onSelect={() => column.toggleSorting(false)}>
            <Icons.chevronUp aria-hidden="true" />
            Crescente
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => column.toggleSorting(true)}>
            <Icons.chevronDown aria-hidden="true" />
            Decrescente
          </DropdownMenuItem>
          {column.getCanHide() ? (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuItem onSelect={() => column.toggleVisibility(false)}>
                <Icons.close aria-hidden="true" />
                Ocultar coluna
              </DropdownMenuItem>
            </>
          ) : null}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

export { DataTableColumnHeader, type DataTableColumnHeaderProps };
