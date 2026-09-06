'use client';

import * as React from 'react';
import { useTable, type RowData } from '@tanstack/react-table';

import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Empty, EmptyHeader, EmptyTitle } from '@/components/ui/empty';
import { Icons } from '@/components/ui/icons';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

import { dataTableFeatures, type DataTableColumnDef } from './data-table-features';
import { DataTablePagination } from './data-table-pagination';
import { SkeletonDataTable } from './skeleton';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from './table';

type DataTableProps<TData extends RowData> = {
  columns: DataTableColumnDef<TData>[];
  data: TData[];
  className?: string;
  columnLabels?: Record<string, string>;
  emptyMessage?: string;
  filterColumn?: string;
  filterPlaceholder?: string;
  loading?: boolean;
  pageSize?: number;
  pageSizeOptions?: number[];
  selectable?: boolean;
  showColumnVisibility?: boolean;
};

function DataTable<TData extends RowData>({
  columns,
  data,
  className,
  columnLabels = {},
  emptyMessage = 'Nenhum resultado encontrado.',
  filterColumn,
  filterPlaceholder = 'Pesquisar...',
  loading = false,
  pageSize = 10,
  pageSizeOptions = [10, 20, 30, 50],
  selectable = true,
  showColumnVisibility = true,
}: DataTableProps<TData>) {
  const selectionColumn = React.useMemo<DataTableColumnDef<TData>>(
    () => ({
      id: 'select',
      header: ({ table }) => (
        <Checkbox
          checked={
            table.getIsAllPageRowsSelected() ||
            (table.getIsSomePageRowsSelected() && 'indeterminate')
          }
          onCheckedChange={(value) => table.toggleAllPageRowsSelected(Boolean(value))}
          aria-label="Selecionar todas as linhas desta página"
        />
      ),
      cell: ({ row }) => (
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(value) => row.toggleSelected(Boolean(value))}
          aria-label="Selecionar linha"
        />
      ),
      enableHiding: false,
      enableSorting: false,
    }),
    [],
  );

  const resolvedColumns = React.useMemo(
    () => (selectable ? [selectionColumn, ...columns] : columns),
    [columns, selectable, selectionColumn],
  );

  const table = useTable({
    features: dataTableFeatures,
    columns: resolvedColumns,
    data,
    enableRowSelection: selectable,
    initialState: {
      pagination: {
        pageIndex: 0,
        pageSize,
      },
    },
  });

  const filterableColumn = filterColumn ? table.getColumn(filterColumn) : undefined;
  const hideableColumns = table
    .getAllColumns()
    .filter((column) => column.getCanHide() && column.accessorFn);

  if (loading) {
    return <SkeletonDataTable className={className} />;
  }

  return (
    <div data-slot="data-table" className={cn('w-full space-y-4', className)}>
      {filterableColumn || (showColumnVisibility && hideableColumns.length > 0) ? (
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          {filterableColumn ? (
            <Input
              value={(filterableColumn.getFilterValue() as string) ?? ''}
              onChange={(event) => filterableColumn.setFilterValue(event.target.value)}
              placeholder={filterPlaceholder}
              aria-label={filterPlaceholder}
              className="sm:max-w-md"
            />
          ) : null}
          {showColumnVisibility && hideableColumns.length > 0 ? (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button type="button" variant="outline" className="sm:ml-auto">
                  <Icons.columns aria-hidden="true" />
                  Colunas
                  <Icons.chevronDown aria-hidden="true" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-56">
                <DropdownMenuLabel>Exibir colunas</DropdownMenuLabel>
                <DropdownMenuSeparator />
                {hideableColumns.map((column) => (
                  <DropdownMenuCheckboxItem
                    key={column.id}
                    checked={column.getIsVisible()}
                    onCheckedChange={(value) => column.toggleVisibility(Boolean(value))}
                  >
                    {columnLabels[column.id] ?? column.id}
                  </DropdownMenuCheckboxItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          ) : null}
        </div>
      ) : null}

      <div className="overflow-hidden rounded-md border">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder ? null : <table.FlexRender header={header} />}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows.length > 0 ? (
              table.getRowModel().rows.map((row) => (
                <TableRow key={row.id} data-state={row.getIsSelected() ? 'selected' : undefined}>
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      <table.FlexRender cell={cell} />
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={resolvedColumns.length} className="h-40">
                  <Empty className="border-0">
                    <EmptyHeader>
                      <EmptyTitle>{emptyMessage}</EmptyTitle>
                    </EmptyHeader>
                  </Empty>
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <DataTablePagination
        table={table}
        pageSizeOptions={pageSizeOptions}
        showSelection={selectable}
      />
    </div>
  );
}

export { DataTable, type DataTableProps };
