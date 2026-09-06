import type { ReactTable, RowData } from '@tanstack/react-table';

import { Button } from '@/components/ui/button';
import { Icons } from '@/components/ui/icons';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

import type { DataTableFeatures } from './data-table-features';

type DataTablePaginationProps<TData extends RowData> = {
  table: ReactTable<DataTableFeatures, TData>;
  pageSizeOptions?: number[];
  showSelection?: boolean;
};

function DataTablePagination<TData extends RowData>({
  table,
  pageSizeOptions = [10, 20, 30, 50],
  showSelection = false,
}: DataTablePaginationProps<TData>) {
  return (
    <div className="flex flex-col gap-4 px-2 text-lg sm:flex-row sm:items-center sm:justify-between">
      <div className="font-extralight text-muted-foreground">
        {showSelection
          ? `${table.getFilteredSelectedRowModel().rows.length} de ${table.getFilteredRowModel().rows.length} linha(s) selecionada(s).`
          : `${table.getFilteredRowModel().rows.length} linha(s).`}
      </div>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="flex items-center gap-2">
          <span className="whitespace-nowrap font-extralight">Linhas por página</span>
          <Select
            value={`${table.state.pagination.pageSize}`}
            onValueChange={(value) => table.setPageSize(Number(value))}
          >
            <SelectTrigger className="w-24 px-3 py-2" aria-label="Linhas por página">
              <SelectValue />
            </SelectTrigger>
            <SelectContent side="top">
              {pageSizeOptions.map((pageSize) => (
                <SelectItem key={pageSize} value={`${pageSize}`}>
                  {pageSize}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="min-w-32 text-center font-extralight">
          Página {table.state.pagination.pageIndex + 1} de {Math.max(table.getPageCount(), 1)}
        </div>
        <div className="grid grid-cols-4 gap-2">
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={() => table.firstPage()}
            disabled={!table.getCanPreviousPage()}
            aria-label="Primeira página"
          >
            <Icons.chevronLeft className="-mr-2" aria-hidden="true" />
            <Icons.chevronLeft aria-hidden="true" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={() => table.previousPage()}
            disabled={!table.getCanPreviousPage()}
            aria-label="Página anterior"
          >
            <Icons.chevronLeft aria-hidden="true" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={() => table.nextPage()}
            disabled={!table.getCanNextPage()}
            aria-label="Próxima página"
          >
            <Icons.chevronRight aria-hidden="true" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={() => table.lastPage()}
            disabled={!table.getCanNextPage()}
            aria-label="Última página"
          >
            <Icons.chevronRight className="-mr-2" aria-hidden="true" />
            <Icons.chevronRight aria-hidden="true" />
          </Button>
        </div>
      </div>
    </div>
  );
}

export { DataTablePagination, type DataTablePaginationProps };
