'use client';

import * as React from 'react';

import {
  Sidebar,
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
  useSidebar,
} from '@/components/layouts/sidebar';
import { cn } from '@/lib/utils';

type AppShellProps = React.ComponentProps<typeof SidebarProvider> & {
  navbarHeight?: string;
};

function AppShell({ className, navbarHeight = '4rem', style, ...props }: AppShellProps) {
  return (
    <SidebarProvider
      data-slot="app-shell"
      className={cn(
        'h-svh w-full overflow-hidden bg-app-shell pt-(--app-shell-navbar-height)',
        className,
      )}
      style={
        {
          '--app-shell-navbar-height': navbarHeight,
          ...style,
        } as React.CSSProperties
      }
      {...props}
    />
  );
}

function AppShellNavbar({ className, ...props }: React.ComponentProps<'nav'>) {
  return (
    <nav
      data-slot="app-shell-navbar"
      className={cn(
        'fixed inset-x-0 top-0 z-30 flex h-(--app-shell-navbar-height) w-full items-center justify-between gap-4 bg-app-shell px-[19px] text-app-shell-foreground',
        className,
      )}
      {...props}
    />
  );
}

function AppShellTrigger({ className, ...props }: React.ComponentProps<typeof SidebarTrigger>) {
  const { state } = useSidebar();

  return (
    <SidebarTrigger
      data-slot="app-shell-trigger"
      className={cn(
        'shrink-0 text-app-shell-foreground transition-transform hover:bg-app-shell-accent hover:text-app-shell-accent-foreground',
        state === 'collapsed' && 'md:-translate-x-[9px]',
        className,
      )}
      {...props}
    />
  );
}

function AppShellSidebar({
  className,
  collapsible = 'icon',
  ...props
}: React.ComponentProps<typeof Sidebar>) {
  return (
    <Sidebar
      data-slot="app-shell-sidebar"
      collapsible={collapsible}
      className={cn(
        'fixed top-(--app-shell-navbar-height) h-[calc(100svh-var(--app-shell-navbar-height))] group-data-[side=left]:border-r-0 group-data-[side=right]:border-l-0',
        className,
      )}
      {...props}
    />
  );
}

function AppShellMain({ className, ...props }: React.ComponentProps<typeof SidebarInset>) {
  return (
    <SidebarInset
      data-slot="app-shell-main"
      className={cn(
        'm-0 min-h-0 min-w-0 flex-1 self-stretch overflow-hidden rounded-t-xl border-0 bg-card shadow-2xl shadow-primary/20',
        className,
      )}
      {...props}
    />
  );
}

function AppShellContent({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="app-shell-content"
      className={cn(
        // `[&>*]:shrink-0`: num flex column com altura definida, os filhos
        // encolhem em vez de transbordar — o conteúdo é cortado e o
        // `overflow-auto` nunca chega a ter o que rolar. Resolver aqui evita
        // que cada consumidor precise lembrar de um `shrink-0` no próprio card.
        'flex w-full flex-1 flex-col overflow-auto bg-background p-4 sm:p-6 [&>*]:shrink-0',
        className,
      )}
      {...props}
    />
  );
}

export {
  AppShell,
  AppShellContent,
  AppShellMain,
  AppShellNavbar,
  AppShellSidebar,
  AppShellTrigger,
  type AppShellProps,
};
