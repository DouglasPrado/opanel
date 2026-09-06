import type { ComponentType } from 'react'

export type PageModules = Record<string, { default: ComponentType }>

/**
 * Resolves an Inertia page name to its component.
 *
 * A missing page must fail by name. The alternative — a blank screen — is the
 * failure mode doc 10 §25 rules out: every state the interface can be in has to
 * be legible, and "nothing rendered" tells an operator nothing.
 */
export function resolvePage(pages: PageModules, name: string): ComponentType {
  const page = pages[`../pages/${name}.tsx`]

  if (!page) {
    const available = Object.keys(pages)
      .map((path) => path.replace('../pages/', '').replace('.tsx', ''))
      .sort()

    throw new Error(
      `Inertia page "${name}" was not found in app/frontend/pages/. ` +
        `Available pages: ${available.length > 0 ? available.join(', ') : '(none)'}`,
    )
  }

  return page.default
}
