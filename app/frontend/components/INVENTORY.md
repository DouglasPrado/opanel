# Component inventory

The versioned catalogue of the component library imported from the existing
`gba.dev` design system (SC-07, Goal §17). **No new design system was created and
none may be.**

This file is what the **Reuse Gate** (Annex I §6.3) is evaluated against. From
M00-05 on, "no equivalent component existed" is a claim that is checked here, not
an opinion. Before creating a component:

1. search this inventory by name, responsibility and appearance;
2. if it is listed under [Available upstream](#available-upstream-not-imported),
   import it — do not rebuild it;
3. try composing the primitives below;
4. try a small, tested variant;
5. only then create something new, and say in the Story Report why 1–4 did not fit.

`app/frontend/pages/Gallery.tsx` renders every entry (development and test only,
at `/gallery`). `spec/frontend/component_inventory_spec.rb` fails when the disk,
the gallery registry and this file disagree, so the inventory cannot age in
silence.

**Origin:** `gba.dev/packages/components` — shadcn/ui base, Radix primitives,
Tailwind v4, `class-variance-authority`. Imports were copied with their contracts
and appearance intact; nothing was redesigned. The `@/components/...`,
`@/lib/utils` and `@/hooks/...` import paths resolve unchanged because
`app/frontend` is Opanel's `@/` root.

**Theme:** `app/frontend/styles/design-system.css` owns the tokens
(`background`, `foreground`, `card`, `muted`, `primary`, `secondary`,
`destructive`, `success`, `danger`, `border`, `ring`, `sidebar`, `chart-*`,
`title`, `subtitle`, the gray ramp). Dark mode is the `dark` class on a root
element. A component that needs a new colour adds a token there; it never
hardcodes a value.

**Loading state:** every component exports a `Skeleton<Name>` counterpart. Use it
for the loading state of doc 10 §25 rather than inventing a placeholder.

---

## ui — primitives

| Component | Responsibility | Public props | Use when | Do **not** use when |
|---|---|---|---|---|
| `accordion` | Vertically stacked, collapsible sections. | `Accordion(type, collapsible, value)`, `AccordionItem(value)`, `AccordionTrigger`, `AccordionContent` | Grouping optional detail on a page that is already dense. | The content must be visible for scanning or comparison — use `tabs` or a plain list. |
| `alert` | Inline, non-blocking message about the current context. | `Alert(variant)`, `AlertTitle`, `AlertDescription`, `AlertAction` | Reporting a condition the user should notice without interrupting them. | The user must decide before proceeding — use `alert-dialog`. |
| `alert-dialog` | Modal that interrupts to confirm a consequential action. | `AlertDialog`, `AlertDialogTrigger`, `AlertDialogContent`, `AlertDialogHeader/Title/Description/Footer`, `AlertDialogAction`, `AlertDialogCancel`, `AlertDialogMedia` | Destructive or irreversible operations: delete, force-new-cluster, rotate. | For anything routine — a modal that appears often stops being read. |
| `aspect-ratio` | Locks a child to a ratio. | `AspectRatio(ratio)` | Media and preview panes that must not shift layout while loading. | Content whose height is driven by text. |
| `avatar` | Identity image with a text fallback and optional badge/group. | `Avatar`, `AvatarImage`, `AvatarFallback`, `AvatarGroup`, `AvatarGroupCount`, `AvatarBadge` | Representing a user or an actor in a list, a header or an audit entry. | Representing a resource — use `icons` or `marker`. |
| `badge` | Short, static status or category label. | `Badge(variant)`, `badgeVariants` | Service state, environment, counts next to a title. | Something clickable — use `button` or `toggle`. |
| `breadcrumb` | Position within the Team → Project → Environment → Service hierarchy. | `Breadcrumb`, `BreadcrumbList`, `BreadcrumbItem`, `BreadcrumbLink`, `BreadcrumbPage`, `BreadcrumbSeparator`, `BreadcrumbEllipsis` | Any page nested below a Project. | Flat navigation between peers — use `tabs` or `navigation-menu`. |
| `button` | The action primitive. | `Button(variant: default/outline/secondary/success/ghost/destructive/link, size: default/xs/sm/lg/icon*)`, `buttonVariants` | Every action. | Navigation that should be a link — pass `asChild` with an anchor instead of faking it. |
| `button-group` | Related actions joined into one control. | `ButtonGroup(orientation)`, `ButtonGroupSeparator`, `ButtonGroupText`, `buttonGroupVariants` | A primary action with a split menu, or an action plus its current value. | Unrelated actions that happen to sit together. |
| `card` | Bounded surface for one subject. | `Card`, `CardHeader`, `CardTitle`, `CardDescription`, `CardAction`, `CardContent`, `CardFooter` | Resource summaries in a grid or a column. | Dense tabular data — use `table`. |
| `checkbox` | Independent boolean. | `Checkbox(checked, defaultChecked, onCheckedChange, disabled)` | Options that are not mutually exclusive; row selection. | An immediate-effect setting — use `switch`. |
| `collapsible` | One region that opens and closes. | `Collapsible(open, defaultOpen, onOpenChange)`, `CollapsibleTrigger`, `CollapsibleContent` | Progressive disclosure of a single block. | Several sibling sections — use `accordion`. |
| `context-menu` | Actions on right-click. | `ContextMenu`, `ContextMenuTrigger`, `ContextMenuContent`, `ContextMenuItem`, `ContextMenuCheckboxItem`, `ContextMenuRadioGroup/RadioItem`, `ContextMenuSub*`, `ContextMenuLabel`, `ContextMenuSeparator`, `ContextMenuShortcut` | A secondary path to actions that are also reachable elsewhere. | The only way to reach an action — it is invisible and unreachable on touch. |
| `dialog` | General modal. `Modal*` is the current name; `Dialog*` is the deprecated alias. | `Modal`, `ModalTrigger`, `ModalContent`, `ModalHeader/Title/Description/Footer`, `ModalOverlay`, `ModalPortal`, `ModalClose` | A focused task that should not lose the page behind it. | Destructive confirmation — use `alert-dialog`. Long forms — use a page. |
| `direction` | Supplies reading direction to the primitives below it. | `DirectionProvider(dir)`, `useDirection()` | Wrapping the app shell once. | Per component — direction is a document-level concern. |
| `dropdown-menu` | Actions or options from a trigger. | `DropdownMenu`, `DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem`, `DropdownMenuCheckboxItem`, `DropdownMenuRadioGroup/RadioItem`, `DropdownMenuLabel`, `DropdownMenuSeparator`, `DropdownMenuShortcut`, `DropdownMenuSub*` | Row actions, account menus, overflow. | Choosing a value in a form — use `select`. |
| `empty` | The empty state of a collection. | `Empty`, `EmptyHeader`, `EmptyMedia(variant)`, `EmptyTitle`, `EmptyDescription`, `EmptyContent` | Every list that can be empty (doc 10 §25 — an empty state is a required state). | An error or a permission denial — those are different states and must read differently. |
| `field` | Label, control, description and error as one unit. | `Field(orientation)`, `FieldLabel`, `FieldDescription`, `FieldError`, `FieldTitle`, `FieldContent`, `FieldGroup`, `FieldSet`, `FieldLegend`, `FieldSeparator` | Every form control. | Read-only display — use `item` or a definition list. |
| `hover-card` | Preview on hover. | `HoverCard(openDelay, closeDelay)`, `HoverCardTrigger`, `HoverCardContent` | Enriching a reference — a digest, a node, an actor. | Anything essential: hover does not exist on touch. |
| `icons` | The icon set: Hugeicons (`Icons.*`) and animated line icons (`LineMdIcon`). | `Icons.<name>(size, className)`, `LineMdIcon(icon, className)`, `LineMdIcons` | Any icon. | Inlining an SVG of your own — add it here so the set stays one set. |
| `input` | Single-line text control. | `Input(type, value, defaultValue, disabled, aria-invalid, …)` | Text, numbers, search. | A secret. No secret input was imported — see [Available upstream](#available-upstream-not-imported). |
| `input-group` | An input with attached addons or buttons. | `InputGroup`, `InputGroupAddon(align)`, `InputGroupInput`, `InputGroupTextarea`, `InputGroupButton`, `InputGroupText` | Prefixes, suffixes, inline actions such as copy or reveal. | The addon is really a separate action — keep it outside the field. |
| `item` | One row of a list: media, content, actions. | `Item(variant, size)`, `ItemMedia`, `ItemContent`, `ItemTitle`, `ItemDescription`, `ItemActions`, `ItemHeader`, `ItemFooter`, `ItemGroup`, `ItemSeparator` | Resource lists that are not tabular. | Comparable columns — use `table`. |
| `kbd` | Keyboard key. | `Kbd`, `KbdGroup` | Documenting a shortcut. | Rendering arbitrary code — use `<code>`. |
| `label` | Accessible label bound to a control. | `Label(htmlFor)` | Any control not already wrapped by `field`. | Section headings — use `title`. |
| `marker` | Small inline status marker with an icon. | `Marker(variant)`, `MarkerIcon`, `MarkerContent`, `markerVariants` | Drift, health and convergence indicators next to a resource. | Long text — it is a marker, not a banner. |
| `menubar` | Persistent horizontal menu bar. | `Menubar`, `MenubarMenu`, `MenubarTrigger`, `MenubarContent`, `MenubarItem`, `MenubarCheckboxItem`, `MenubarRadioGroup/RadioItem`, `MenubarSub*`, `MenubarLabel`, `MenubarSeparator`, `MenubarShortcut` | Dense tool surfaces with many grouped commands. | Primary navigation — use the app shell's sidebar. |
| `message` | A message in a stream, with author and timestamp. | `MessageGroup`, `Message`, `MessageAvatar`, `MessageHeader`, `MessageContent`, `MessageFooter` | Operation timelines, agent conversations, audit narratives. | Log lines — those are dense and monospaced. |
| `navigation-menu` | Horizontal navigation with optional panels. | `NavigationMenu`, `NavigationMenuList`, `NavigationMenuItem`, `NavigationMenuTrigger`, `NavigationMenuContent`, `NavigationMenuLink`, `NavigationMenuIndicator`, `NavigationMenuViewport`, `navigationMenuTriggerStyle` | Top-level sections. | Actions — navigation is not a command surface. |
| `pagination` | Page controls for a collection. | `Pagination`, `PaginationContent`, `PaginationItem`, `PaginationLink(isActive)`, `PaginationPrevious`, `PaginationNext`, `PaginationEllipsis` | Every potentially large collection — pagination is mandatory, not optional. | Collections with a hard small bound. |
| `popover` | Anchored panel with content or a small form. | `Popover`, `PopoverTrigger`, `PopoverAnchor`, `PopoverContent`, `PopoverHeader`, `PopoverTitle`, `PopoverDescription` | Filters, quick edits, extra context. | A list of actions — use `dropdown-menu`. |
| `progress` | Determinate progress. | `Progress(value, max)` | Work with a known total: uploads, rollout of N tasks. | Unknown duration — use `spinner`. |
| `radio-group` | One choice from a small set. | `RadioGroup(value, defaultValue, onValueChange)`, `RadioGroupItem(value)`, `RadioGroupChoice` | Two to five mutually exclusive options that should all be visible. | More than about five — use `select`. |
| `scroll-area` | Styled scroll container. | `ScrollArea(type)`, `ScrollBar(orientation)` | Bounded regions: log panes, long lists inside a card. | The page itself. |
| `select` | Choose one value from many. | `Select(value, defaultValue, onValueChange)`, `SelectTrigger`, `SelectValue`, `SelectContent`, `SelectItem`, `SelectGroup`, `SelectLabel`, `SelectSeparator`, `SelectScrollUpButton/DownButton` | Environment, region, policy pickers. | Free text or search over many values — the upstream `combobox` covers that. |
| `separator` | Visual or semantic divider. | `Separator(orientation, decorative)` | Separating groups inside a surface. | As spacing — use layout. |
| `sheet` | Panel sliding from an edge. | `Sheet`, `SheetTrigger`, `SheetContent(side)`, `SheetHeader`, `SheetTitle`, `SheetDescription`, `SheetFooter`, `SheetClose` | Detail and timeline panels that should keep the list in view. | A confirmation — use `alert-dialog`. |
| `skeleton` | Loading placeholder, and the factory the per-component skeletons use. | `Skeleton`, `SkeletonLayout(variant)`, `createComponentSkeleton` | Any loading state. Prefer the component's own `Skeleton<Name>`. | Long waits with a known total — use `progress`. |
| `slider` | Numeric value on a range. | `Slider(value, defaultValue, onValueChange, min, max, step)` | Thresholds and limits where the range matters more than the exact number. | Exact numeric entry — use `input`. |
| `spinner` | Indeterminate activity. | `Spinner(className)` | Waiting with no known total. | Blocking the whole page for a long operation — Operations are asynchronous and get a timeline. |
| `switch` | Immediate-effect boolean setting. | `Switch(checked, defaultChecked, onCheckedChange, disabled)` | A setting that applies as soon as it is flipped. | Inside a form that is submitted later — use `checkbox`. |
| `table` | Tabular data, plus the composed `DataTable` over `@tanstack/react-table`. | `Table`, `TableHeader`, `TableBody`, `TableFooter`, `TableRow`, `TableHead`, `TableCell`, `TableCaption`, `DataTable(columns, data, …)`, `DataTableColumnHeader`, `DataTablePagination`, `dataTableFeatures` | Comparable columns: services, tasks, nodes, operations, audit. | A handful of items with no columns to compare — use `item`. |
| `tabs` | Switch between sibling views of one subject. | `Tabs(value, defaultValue, onValueChange)`, `TabsList(variant)`, `TabsTrigger(value)`, `TabsContent(value)`, `tabsListVariants` | Overview / Logs / Settings on one resource. | Navigating between different resources — that is routing. |
| `textarea` | Multi-line text. | `Textarea(value, defaultValue, rows, …)` | Descriptions, reasons, annotations. | Structured configuration — model the fields. |
| `title` | Page or section heading with an optional subtitle and icon. | `Title(title, subtitle, icon, as, size, animated)`, `titleVariants`, `subtitleVariants` | Page and section headers. | Inside a `card` — use `CardTitle`. |
| `toggle` | Two-state button. | `Toggle(pressed, defaultPressed, onPressedChange, variant, size)`, `toggleVariants` | Sticky view options: follow logs, wrap lines. | A form boolean — use `checkbox` or `switch`. |
| `toggle-group` | A set of toggles, single or multiple. | `ToggleGroup(type, value, defaultValue, onValueChange)`, `ToggleGroupItem(value)` | Time ranges, view modes. | Navigation — use `tabs`. |
| `tooltip` | Short label on hover or focus. | `TooltipProvider`, `Tooltip`, `TooltipTrigger`, `TooltipContent` | Naming an icon-only control. | Anything essential, or more than a sentence — hover is not reachable on touch. |

## shared — composed, reused by several features

| Component | Responsibility | Public props | Use when | Do **not** use when |
|---|---|---|---|---|
| `notifications` | Notification bell with an unread count and a list. | `notifications: NotificationItem[]`, `unreadCount`, `label`, `emptyLabel`, `viewAllLabel`, `viewAllHref`, `onNotificationSelect`, `onViewAll`, `disabled`, `align`, `side` | The app shell's notification surface. | Inline page feedback — use `alert` or a flash prop. |
| `profile` | Account menu: identity, settings, sign out. | `name`, `email`, `avatarSrc`, `avatarAlt`, `fallback`, `settingsLabel`, `logoutLabel`, `onSettings`, `onLogout`, `disabled`, `align`, `side` | The app shell's account menu. | Displaying a user inside a list — use `avatar` with `item`. |
| `states` | The universal states of doc 10 §25 as components: loading, empty, no permission, error, offline, stale. | `LoadingState(label, lines)`, `EmptyState(title, description, action)`, `NoPermissionState(title, description)`, `ErrorState(title, description, requestId, onRetry)`, `OfflineState(lastSeenAt, description)`, `StaleState(observedAt)` | Every page that can be loading, empty, forbidden, broken, offline or stale — which is every page. | A one-off inline message — use `alert` directly. |
| `team-switcher` | The Team the operator is acting in, and the way to change it. | `teams: TeamOption[]`, `currentTeamId`, `onSelect`, `onCreate`, `label`, `className` | The app shell's header. | Choosing a Team inside a form — use `select`. |
| `environment-badge` | Which Environment a page is showing, `PRODUCTION` persistently. | `kind: 'PRODUCTION' \| 'STAGING' \| 'DEVELOPMENT' \| 'PREVIEW'`, `className` | Any page or row scoped to an Environment. | A generic status label — use `badge`. |

## layouts — shells, navigation, page layouts

| Component | Responsibility | Public props | Use when | Do **not** use when |
|---|---|---|---|---|
| `app-shell` | The application frame: navbar, sidebar, main region. | `AppShell(navbarHeight, …SidebarProvider props)`, `AppShellNavbar`, `AppShellTrigger`, `AppShellSidebar`, `AppShellMain`, `AppShellContent` | Every authenticated page of the Control Plane. | Sign-in, error and other standalone pages. |
| `panel-layout` | The frame every authenticated page renders inside: navbar with team switcher and account menu, product-first sidebar. | `PanelLayout(children, section)`, `PANEL_NAVIGATION` | Every authenticated page of the Control Plane. | Sign-in, sign-up and the error page — they are standalone by design. |
| `sidebar` | Collapsible navigation sidebar with groups, menus and sub-menus. | `SidebarProvider(defaultOpen, open, onOpenChange)`, `Sidebar(side, variant, collapsible)`, `SidebarHeader/Content/Footer`, `SidebarGroup*`, `SidebarMenu`, `SidebarMenuItem`, `SidebarMenuButton(isActive, tooltip)`, `SidebarMenuAction`, `SidebarMenuBadge`, `SidebarMenuSub*`, `SidebarMenuSkeleton`, `SidebarTrigger`, `SidebarRail`, `SidebarInset`, `SidebarInput`, `SidebarSeparator`, `useSidebar()` | Inside `app-shell`. | Standalone — it expects `SidebarProvider`. |

---

## Available upstream, not imported

These exist in `gba.dev/packages/components` and were **deliberately not
imported**: each pulls in a dependency M00 has no use for, and the M00 scope
forbids installing a dependency "to use later".

**They are still the answer to "does an equivalent exist?" — the answer is yes.**
A Story that needs one imports it from upstream with its Dependency
Justification, and adds it here. Rebuilding one of these is a review finding.

| Component | Upstream dependency it needs |
|---|---|
| `bubble`, `color-palette` | none — omitted only because nothing uses them yet |
| `carousel` | `embla-carousel-react` |
| `chart` | `recharts` |
| `combobox` | `@base-ui/react` |
| `command` | `cmdk` |
| `drawer` | `vaul` |
| `email-template`, `upgrade-card` | none / `framer-motion` |
| `forms`, `field-address`, `field-password`, `field-upload`, `field-document` | `zod` |
| `gantt` | `date-fns`, `@dnd-kit/*` |
| `input-cep`, `input-cnpj`, `input-cpf`, `input-credit-card`, `input-currency`, `input-date`, `input-email`, `input-phone`, `input-website`, `input-upload` | `zod` — and most encode Brazilian document formats the Control Plane does not handle |
| `input-otp` | `input-otp` — needed by MFA in M11 |
| `message-scroller`, `questionnaire` | `@shadcn/react` |
| `resizable` | `react-resizable-panels` |
| `sortable` | `@dnd-kit/*` |
| `toast` | `sonner` |
| `tree` | `@headless-tree/*` |

## Security notes

- **No imported component reads or writes the clipboard.** A component that copies
  a secret to the clipboard without an explicit user confirmation is forbidden
  (doc 10 §28), and `spec/frontend/component_inventory_spec.rb` asserts the
  absence of any Clipboard API call in this tree.
- **No secret-input component was imported.** When one is needed, it arrives with
  the Vault work in M03: `type="password"`, no autofill of a secret value, reveal
  as an explicit, re-authenticated and audited action — never an automatic copy.
- Components render what they are given. Keeping a secret out of a prop is the
  caller's job, and shared props are checked for it in
  `spec/security/inertia_shared_props_spec.rb`.
