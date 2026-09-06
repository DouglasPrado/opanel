# app/frontend

The Control Plane interface: React + TypeScript pages served by Rails over
Inertia, bundled by Vite, styled with Tailwind. One application — not a separate
frontend project (SC-01).

```text
components/
  ui/        primitives: Button, Input, Dialog, Tabs, ...
  shared/    composed components reused by several features
  features/  components belonging to one domain
  layouts/   shells, navigation, page layouts
pages/       Inertia pages — one file per component name
entrypoints/ Vite entry points
hooks/       reusable React hooks
lib/         pure helpers, no React
types/       shared TypeScript types
```

`@/` resolves to this directory.

## Rules

**Server-driven props first.** A page renders what the Control Plane sent. Local
state is for what the browser genuinely owns — a disclosure that is open, a field
being typed into, a menu.

**No global store for state that belongs to one page or feature.** If two pages
need the same data, the server sends it to both. Introducing a store to avoid a
prop is how a second source of truth starts (Annex I §6.4).

**Remote state and visual state stay separate.** Realtime updates refresh props
predictably; the browser never becomes a second source of truth about the
cluster.

**Never import server-only code.** Nothing under `app/frontend/` may reach a
database client, the Docker API, a filesystem path or any Node/server module.
There is no build in which that would work, and fitness function AF-04 (M00-13)
fails the build if it appears.

**No REST endpoint built only to feed this tree.** Inertia carries the props. The
public API exists for MCP, the CLI and external automation, and it shares the same
Application Layer rather than duplicating rules per delivery channel.

**Nothing sensitive in shared props.** They are serialized into the HTML of every
response. A token placed there is a token published.

**Reuse before creation.** From M00-05 the component inventory
(`components/INVENTORY.md`) is what the Reuse Gate is evaluated against: search it,
compose primitives, add a tested variant, and only then create something new
(Annex I §6.3).

**Test selectors are semantic.** Roles, accessible names and stable `data-testid`
attributes. A CSS class is a styling decision and breaks the moment styling
changes; using one as a selector is rejected by lint (M00-09).

**Every state is a rendered state.** Loading, empty, no permission, offline,
stale, operation running and partial failure are states the interface has to be
able to show. A page that can only render its happy path is incomplete
(doc 10 §25).

## Styling

Tailwind v4, configured in `entrypoints/application.css`. Base tokens —
`surface`, `border`, `content`, `accent`, `danger`, `warning`, `success` — are
defined there, and dark mode follows the system unless `data-theme` is set on
`<html>`. A component that needs a new colour adds a token; it does not hardcode a
hex value.
