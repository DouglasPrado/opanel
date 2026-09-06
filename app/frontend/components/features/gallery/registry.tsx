import { useState, type ReactNode } from 'react';

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Alert, AlertAction, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { AspectRatio } from '@/components/ui/aspect-ratio';
import { Avatar, AvatarFallback, AvatarGroup } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from '@/components/ui/breadcrumb';
import { Button } from '@/components/ui/button';
import { ButtonGroup, ButtonGroupSeparator, ButtonGroupText } from '@/components/ui/button-group';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from '@/components/ui/context-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { DirectionProvider } from '@/components/ui/direction';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from '@/components/ui/empty';
import { Field, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field';
import { HoverCard, HoverCardContent, HoverCardTrigger } from '@/components/ui/hover-card';
import { Icons, LineMdIcon } from '@/components/ui/icons';
import { Input } from '@/components/ui/input';
import { InputGroup, InputGroupAddon, InputGroupInput } from '@/components/ui/input-group';
import {
  Item,
  ItemActions,
  ItemContent,
  ItemDescription,
  ItemMedia,
  ItemTitle,
} from '@/components/ui/item';
import { Kbd, KbdGroup } from '@/components/ui/kbd';
import { Label } from '@/components/ui/label';
import { Marker, MarkerContent, MarkerIcon } from '@/components/ui/marker';
import {
  Menubar,
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarTrigger,
} from '@/components/ui/menubar';
import { Message, MessageContent, MessageGroup, MessageHeader } from '@/components/ui/message';
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  navigationMenuTriggerStyle,
} from '@/components/ui/navigation-menu';
import {
  Pagination,
  PaginationContent,
  PaginationItem,
  PaginationLink,
  PaginationNext,
  PaginationPrevious,
} from '@/components/ui/pagination';
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from '@/components/ui/popover';
import { Progress } from '@/components/ui/progress';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Separator } from '@/components/ui/separator';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet';
import { Skeleton } from '@/components/ui/skeleton';
import { Slider } from '@/components/ui/slider';
import { Spinner } from '@/components/ui/spinner';
import { Switch } from '@/components/ui/switch';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';
import { Title } from '@/components/ui/title';
import { Toggle } from '@/components/ui/toggle';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';

import { Notifications } from '@/components/shared/notifications';
import { Profile } from '@/components/shared/profile';

import {
  AppShell,
  AppShellContent,
  AppShellMain,
  AppShellNavbar,
  AppShellSidebar,
  AppShellTrigger,
} from '@/components/layouts/app-shell';
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from '@/components/layouts/sidebar';

export type GalleryCategory = 'ui' | 'shared' | 'layouts';

export interface GalleryEntry {
  /** Directory name under app/frontend/components/<category>/. */
  name: string;
  category: GalleryCategory;
  render: () => ReactNode;
}

function ControlledSwitch() {
  const [on, setOn] = useState(false);
  return <Switch checked={on} onCheckedChange={setOn} aria-label="Toggle example" />;
}

function ControlledSlider() {
  const [value, setValue] = useState([40]);
  return (
    <Slider
      value={value}
      onValueChange={setValue}
      max={100}
      step={1}
      className="w-64"
      aria-label="CPU limit"
    />
  );
}

/**
 * One entry per component directory on disk.
 *
 * `spec/frontend/component_inventory_spec.rb` compares this registry, the
 * directories under app/frontend/components/ and INVENTORY.md, and fails when any
 * of the three drifts from the others — so the inventory cannot silently age.
 */
export const galleryEntries: GalleryEntry[] = [
  {
    name: 'accordion',
    category: 'ui',
    render: () => (
      <Accordion type="single" collapsible className="w-full max-w-sm">
        <AccordionItem value="item-1">
          <AccordionTrigger>Placement constraints</AccordionTrigger>
          <AccordionContent>Constraints decide which nodes may run a task.</AccordionContent>
        </AccordionItem>
      </Accordion>
    ),
  },
  {
    name: 'alert',
    category: 'ui',
    render: () => (
      <Alert>
        <AlertTitle>Rollout paused</AlertTitle>
        <AlertDescription>Two of three tasks are healthy.</AlertDescription>
        <AlertAction>
          <Button size="xs" variant="outline">
            Resume
          </Button>
        </AlertAction>
      </Alert>
    ),
  },
  {
    name: 'alert-dialog',
    category: 'ui',
    render: () => (
      <AlertDialog>
        <AlertDialogTrigger asChild>
          <Button variant="destructive">Delete</Button>
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this service?</AlertDialogTitle>
            <AlertDialogDescription>This cannot be undone.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction>Delete</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    ),
  },
  {
    name: 'aspect-ratio',
    category: 'ui',
    render: () => (
      <AspectRatio ratio={16 / 9} className="bg-muted w-64 rounded-md">
        <div className="text-muted-foreground flex h-full items-center justify-center text-xs">
          16 / 9
        </div>
      </AspectRatio>
    ),
  },
  {
    name: 'avatar',
    category: 'ui',
    render: () => (
      <AvatarGroup>
        <Avatar>
          <AvatarFallback>OP</AvatarFallback>
        </Avatar>
        <Avatar>
          <AvatarFallback>DP</AvatarFallback>
        </Avatar>
      </AvatarGroup>
    ),
  },
  {
    name: 'badge',
    category: 'ui',
    render: () => (
      <div className="flex gap-2">
        <Badge>running</Badge>
        <Badge variant="secondary">pending</Badge>
        <Badge variant="destructive">failed</Badge>
      </div>
    ),
  },
  {
    name: 'breadcrumb',
    category: 'ui',
    render: () => (
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink href="#">Projects</BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbPage>production</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>
    ),
  },
  {
    name: 'button',
    category: 'ui',
    render: () => (
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm">Deploy</Button>
        <Button size="sm" variant="outline">
          Cancel
        </Button>
        <Button size="sm" variant="destructive">
          Delete
        </Button>
        <Button size="sm" disabled>
          Disabled
        </Button>
      </div>
    ),
  },
  {
    name: 'button-group',
    category: 'ui',
    render: () => (
      <ButtonGroup>
        <Button size="sm" variant="outline">
          Scale
        </Button>
        <ButtonGroupSeparator />
        <ButtonGroupText>3 replicas</ButtonGroupText>
      </ButtonGroup>
    ),
  },
  {
    name: 'card',
    category: 'ui',
    render: () => (
      <Card className="w-72">
        <CardHeader>
          <CardTitle>api</CardTitle>
          <CardDescription>3/3 tasks healthy</CardDescription>
        </CardHeader>
        <CardContent className="text-muted-foreground text-sm">sha256:9f2c…</CardContent>
      </Card>
    ),
  },
  {
    name: 'checkbox',
    category: 'ui',
    render: () => (
      <div className="flex items-center gap-2">
        <Checkbox id="gallery-checkbox" defaultChecked />
        <Label htmlFor="gallery-checkbox">Drain before update</Label>
      </div>
    ),
  },
  {
    name: 'collapsible',
    category: 'ui',
    render: () => (
      <Collapsible className="w-64">
        <CollapsibleTrigger asChild>
          <Button size="sm" variant="ghost">
            Environment variables
          </Button>
        </CollapsibleTrigger>
        <CollapsibleContent className="text-muted-foreground pt-2 text-sm">
          4 variables, 2 bound to secrets
        </CollapsibleContent>
      </Collapsible>
    ),
  },
  {
    name: 'context-menu',
    category: 'ui',
    render: () => (
      <ContextMenu>
        <ContextMenuTrigger className="border-border text-muted-foreground flex h-16 w-64 items-center justify-center rounded-md border border-dashed text-sm">
          Right click here
        </ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuItem>Restart</ContextMenuItem>
          <ContextMenuSeparator />
          <ContextMenuItem>View logs</ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>
    ),
  },
  {
    name: 'dialog',
    category: 'ui',
    render: () => (
      <Dialog>
        <DialogTrigger asChild>
          <Button size="sm">Open dialog</Button>
        </DialogTrigger>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Scale service</DialogTitle>
            <DialogDescription>Replicas converge asynchronously.</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button size="sm">Apply</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    ),
  },
  {
    name: 'direction',
    category: 'ui',
    render: () => (
      <DirectionProvider dir="ltr">
        <span className="text-muted-foreground text-sm">
          Provides reading direction to every primitive below it.
        </span>
      </DirectionProvider>
    ),
  },
  {
    name: 'dropdown-menu',
    category: 'ui',
    render: () => (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button size="sm" variant="outline">
            Actions
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuLabel>Service</DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem>Restart</DropdownMenuItem>
          <DropdownMenuItem>Rollback</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    ),
  },
  {
    name: 'empty',
    category: 'ui',
    render: () => (
      <Empty className="w-72">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <Icons.component />
          </EmptyMedia>
          <EmptyTitle>No services yet</EmptyTitle>
          <EmptyDescription>Deploy an image to see it here.</EmptyDescription>
        </EmptyHeader>
      </Empty>
    ),
  },
  {
    name: 'field',
    category: 'ui',
    render: () => (
      <Field className="w-64">
        <FieldLabel htmlFor="gallery-field">Replicas</FieldLabel>
        <Input id="gallery-field" defaultValue="3" aria-invalid />
        <FieldDescription>Desired number of tasks.</FieldDescription>
        <FieldError>Must be at least 1.</FieldError>
      </Field>
    ),
  },
  {
    name: 'hover-card',
    category: 'ui',
    render: () => (
      <HoverCard>
        <HoverCardTrigger asChild>
          <Button size="sm" variant="link">
            sha256:9f2c…
          </Button>
        </HoverCardTrigger>
        <HoverCardContent className="text-sm">
          Immutable digest of the deployed release.
        </HoverCardContent>
      </HoverCard>
    ),
  },
  {
    name: 'icons',
    category: 'ui',
    render: () => (
      <div className="flex items-center gap-3">
        <Icons.cog />
        <Icons.alert />
        <Icons.checkAll />
        <LineMdIcon icon="account" className="size-5" />
      </div>
    ),
  },
  {
    name: 'input',
    category: 'ui',
    render: () => (
      <Input
        className="w-64"
        placeholder="service name"
        defaultValue="api"
        aria-label="Service name"
      />
    ),
  },
  {
    name: 'input-group',
    category: 'ui',
    render: () => (
      <InputGroup className="w-64">
        <InputGroupAddon>https://</InputGroupAddon>
        <InputGroupInput placeholder="api.example.com" aria-label="Custom domain" />
      </InputGroup>
    ),
  },
  {
    name: 'item',
    category: 'ui',
    render: () => (
      <Item className="w-72">
        <ItemMedia>
          <Icons.component />
        </ItemMedia>
        <ItemContent>
          <ItemTitle>api</ItemTitle>
          <ItemDescription>3 replicas · production</ItemDescription>
        </ItemContent>
        <ItemActions>
          <Badge>running</Badge>
        </ItemActions>
      </Item>
    ),
  },
  {
    name: 'kbd',
    category: 'ui',
    render: () => (
      <KbdGroup>
        <Kbd>⌘</Kbd>
        <Kbd>K</Kbd>
      </KbdGroup>
    ),
  },
  {
    name: 'label',
    category: 'ui',
    render: () => <Label htmlFor="gallery-label-input">Image digest</Label>,
  },
  {
    name: 'marker',
    category: 'ui',
    render: () => (
      <Marker>
        <MarkerIcon>
          <Icons.alertCircle />
        </MarkerIcon>
        <MarkerContent>drift detected</MarkerContent>
      </Marker>
    ),
  },
  {
    name: 'menubar',
    category: 'ui',
    render: () => (
      <Menubar>
        <MenubarMenu>
          <MenubarTrigger>Service</MenubarTrigger>
          <MenubarContent>
            <MenubarItem>Restart</MenubarItem>
            <MenubarItem>Rollback</MenubarItem>
          </MenubarContent>
        </MenubarMenu>
      </Menubar>
    ),
  },
  {
    name: 'message',
    category: 'ui',
    render: () => (
      <MessageGroup className="w-72">
        <Message>
          <MessageContent>
            <MessageHeader>reconciler</MessageHeader>
            Converged to the desired revision.
          </MessageContent>
        </Message>
      </MessageGroup>
    ),
  },
  {
    name: 'navigation-menu',
    category: 'ui',
    render: () => (
      <NavigationMenu>
        <NavigationMenuList>
          <NavigationMenuItem>
            <NavigationMenuLink className={navigationMenuTriggerStyle()} href="#">
              Overview
            </NavigationMenuLink>
          </NavigationMenuItem>
        </NavigationMenuList>
      </NavigationMenu>
    ),
  },
  {
    name: 'pagination',
    category: 'ui',
    render: () => (
      <Pagination>
        <PaginationContent>
          <PaginationItem>
            <PaginationPrevious href="#" />
          </PaginationItem>
          <PaginationItem>
            <PaginationLink href="#" isActive>
              1
            </PaginationLink>
          </PaginationItem>
          <PaginationItem>
            <PaginationNext href="#" />
          </PaginationItem>
        </PaginationContent>
      </Pagination>
    ),
  },
  {
    name: 'popover',
    category: 'ui',
    render: () => (
      <Popover>
        <PopoverTrigger asChild>
          <Button size="sm" variant="outline">
            Details
          </Button>
        </PopoverTrigger>
        <PopoverContent>
          <PopoverTitle>Task 1 of 3</PopoverTitle>
          <p className="text-muted-foreground text-sm">Running on node-a since 12m ago.</p>
        </PopoverContent>
      </Popover>
    ),
  },
  {
    name: 'progress',
    category: 'ui',
    render: () => <Progress value={66} className="w-64" aria-label="Rollout progress" />,
  },
  {
    name: 'radio-group',
    category: 'ui',
    render: () => (
      <RadioGroup defaultValue="rolling" className="flex gap-4">
        <div className="flex items-center gap-2">
          <RadioGroupItem value="rolling" id="gallery-rolling" />
          <Label htmlFor="gallery-rolling">Rolling</Label>
        </div>
        <div className="flex items-center gap-2">
          <RadioGroupItem value="recreate" id="gallery-recreate" />
          <Label htmlFor="gallery-recreate">Recreate</Label>
        </div>
      </RadioGroup>
    ),
  },
  {
    name: 'scroll-area',
    category: 'ui',
    render: () => (
      <ScrollArea className="border-border h-24 w-64 rounded-md border p-3">
        <p className="text-muted-foreground text-sm">
          A long stream of reconciliation output that has to scroll inside its own container rather
          than growing the page.
        </p>
      </ScrollArea>
    ),
  },
  {
    name: 'select',
    category: 'ui',
    render: () => (
      <Select defaultValue="production">
        <SelectTrigger className="w-48" aria-label="Environment">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="production">production</SelectItem>
          <SelectItem value="staging">staging</SelectItem>
        </SelectContent>
      </Select>
    ),
  },
  {
    name: 'separator',
    category: 'ui',
    render: () => (
      <div className="w-64">
        <Separator />
      </div>
    ),
  },
  {
    name: 'sheet',
    category: 'ui',
    render: () => (
      <Sheet>
        <SheetTrigger asChild>
          <Button size="sm" variant="outline">
            Open sheet
          </Button>
        </SheetTrigger>
        <SheetContent>
          <SheetHeader>
            <SheetTitle>Operation timeline</SheetTitle>
            <SheetDescription>Every step of the current rollout.</SheetDescription>
          </SheetHeader>
        </SheetContent>
      </Sheet>
    ),
  },
  {
    name: 'skeleton',
    category: 'ui',
    render: () => (
      <div className="flex w-64 flex-col gap-2">
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-2/3" />
      </div>
    ),
  },
  {
    name: 'slider',
    category: 'ui',
    render: () => <ControlledSlider />,
  },
  {
    name: 'spinner',
    category: 'ui',
    render: () => <Spinner />,
  },
  {
    name: 'switch',
    category: 'ui',
    render: () => <ControlledSwitch />,
  },
  {
    name: 'table',
    category: 'ui',
    render: () => (
      <Table className="w-72">
        <TableHeader>
          <TableRow>
            <TableHead>Task</TableHead>
            <TableHead>Node</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow>
            <TableCell>api.1</TableCell>
            <TableCell>node-a</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>api.2</TableCell>
            <TableCell>node-b</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    ),
  },
  {
    name: 'tabs',
    category: 'ui',
    render: () => (
      <Tabs defaultValue="overview" className="w-72">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="text-muted-foreground text-sm">
          3/3 tasks healthy.
        </TabsContent>
        <TabsContent value="logs" className="text-muted-foreground text-sm">
          Streaming from 3 tasks.
        </TabsContent>
      </Tabs>
    ),
  },
  {
    name: 'textarea',
    category: 'ui',
    render: () => (
      <Textarea
        className="w-64"
        defaultValue="Reason for this rollback"
        aria-label="Rollback reason"
      />
    ),
  },
  {
    name: 'title',
    category: 'ui',
    render: () => <Title title="Operations" subtitle="Live view of every running task." />,
  },
  {
    name: 'toggle',
    category: 'ui',
    render: () => (
      <Toggle aria-label="Follow logs">
        <Icons.alert />
      </Toggle>
    ),
  },
  {
    name: 'toggle-group',
    category: 'ui',
    render: () => (
      <ToggleGroup type="single" defaultValue="1h">
        <ToggleGroupItem value="1h">1h</ToggleGroupItem>
        <ToggleGroupItem value="24h">24h</ToggleGroupItem>
      </ToggleGroup>
    ),
  },
  {
    name: 'tooltip',
    category: 'ui',
    render: () => (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button size="sm" variant="outline">
              Hover
            </Button>
          </TooltipTrigger>
          <TooltipContent>Desired revision 12, applied revision 12.</TooltipContent>
        </Tooltip>
      </TooltipProvider>
    ),
  },

  {
    name: 'notifications',
    category: 'shared',
    render: () => (
      <Notifications
        unreadCount={2}
        notifications={[
          { id: '1', title: 'Rollout finished', description: 'api · production', read: false },
          { id: '2', title: 'Certificate renewed', description: 'app.example.com', read: true },
        ]}
      />
    ),
  },
  {
    name: 'profile',
    category: 'shared',
    render: () => <Profile name="Douglas Prado" email="operator@example.com" />,
  },

  {
    name: 'app-shell',
    category: 'layouts',
    render: () => (
      <div className="border-border h-64 w-full overflow-hidden rounded-md border">
        <AppShell navbarHeight="3rem">
          <AppShellNavbar>
            <AppShellTrigger />
            <span className="text-sm font-medium">Opanel</span>
          </AppShellNavbar>
          <AppShellSidebar>
            <SidebarContent>
              <SidebarGroup>
                <SidebarGroupLabel>Project</SidebarGroupLabel>
                <SidebarMenu>
                  <SidebarMenuItem>
                    <SidebarMenuButton>Services</SidebarMenuButton>
                  </SidebarMenuItem>
                </SidebarMenu>
              </SidebarGroup>
            </SidebarContent>
          </AppShellSidebar>
          <AppShellMain>
            <AppShellContent className="text-muted-foreground text-sm">
              Page content
            </AppShellContent>
          </AppShellMain>
        </AppShell>
      </div>
    ),
  },
  {
    name: 'sidebar',
    category: 'layouts',
    render: () => (
      <div className="border-border h-64 w-full overflow-hidden rounded-md border">
        <SidebarProvider>
          <Sidebar collapsible="none">
            <SidebarContent>
              <SidebarGroup>
                <SidebarGroupLabel>Environments</SidebarGroupLabel>
                <SidebarMenu>
                  <SidebarMenuItem>
                    <SidebarMenuButton isActive>production</SidebarMenuButton>
                  </SidebarMenuItem>
                  <SidebarMenuItem>
                    <SidebarMenuButton>staging</SidebarMenuButton>
                  </SidebarMenuItem>
                </SidebarMenu>
              </SidebarGroup>
            </SidebarContent>
          </Sidebar>
        </SidebarProvider>
      </div>
    ),
  },
];
