import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

import '@/entrypoints/application.css'
import { pageTitle } from '@/lib/page-title'
import { resolvePage, type PageModules } from '@/lib/resolve-page'

const pages = import.meta.glob('../pages/**/*.tsx', { eager: true }) as PageModules

createInertiaApp({
  title: pageTitle,
  resolve: (name) => resolvePage(pages, name),
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
