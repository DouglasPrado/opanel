import { Head } from '@inertiajs/react'

import { galleryEntries, type GalleryCategory } from '@/components/features/gallery/registry'

const CATEGORY_LABELS: Record<GalleryCategory, string> = {
  ui: 'ui — primitives',
  shared: 'shared — composed, reused by several features',
  layouts: 'layouts — shells, navigation, page layouts',
}

const CATEGORY_ORDER: GalleryCategory[] = ['ui', 'shared', 'layouts']

/**
 * Visual inspection surface for the imported component library.
 *
 * Development only — the route is not drawn in any other environment. It is the
 * other half of `components/INVENTORY.md`: the inventory says what exists, and
 * this renders it so "an equivalent already exists" can be checked with eyes as
 * well as with a grep.
 */
export default function Gallery() {
  return (
    <>
      <Head title="Component gallery" />

      <main className="mx-auto flex max-w-4xl flex-col gap-10 p-8">
        <header className="flex flex-col gap-1">
          <h1 className="text-2xl font-semibold tracking-tight">Component gallery</h1>
          <p className="text-muted-foreground text-sm">
            {galleryEntries.length} components imported from the existing library. The Reuse Gate
            (Annex I §6.3) is evaluated against this set and against{' '}
            <code>app/frontend/components/INVENTORY.md</code>.
          </p>
        </header>

        {CATEGORY_ORDER.map((category) => {
          const entries = galleryEntries.filter((entry) => entry.category === category)

          return (
            <section key={category} className="flex flex-col gap-6" data-testid={`gallery-${category}`}>
              <h2 className="text-muted-foreground text-xs font-medium tracking-wide uppercase">
                {CATEGORY_LABELS[category]}
              </h2>

              {entries.map((entry) => (
                <article
                  key={`${entry.category}/${entry.name}`}
                  data-testid={`gallery-entry-${entry.name}`}
                  className="border-border flex flex-col gap-3 rounded-lg border p-4"
                >
                  <h3 className="font-mono text-sm">{entry.name}</h3>
                  <div className="flex flex-wrap items-start gap-4">{entry.render()}</div>
                </article>
              ))}
            </section>
          )
        })}
      </main>
    </>
  )
}
