import { createInertiaApp } from '@inertiajs/react';
import { createRoot } from 'react-dom/client';

import '@/entrypoints/application.css';
import { pageTitle } from '@/lib/page-title';
import { resolvePage, type PageModules } from '@/lib/resolve-page';

// Test files live next to the pages they cover; they must never reach the
// bundle. One that did would run its mocking framework in the browser and stop
// the application from mounting — which is exactly how this was found.
const pages = import.meta.glob(['../pages/**/*.tsx', '!../pages/**/*.test.tsx'], {
  eager: true,
}) as PageModules;

createInertiaApp({
  title: pageTitle,
  resolve: (name) => resolvePage(pages, name),
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />);
  },
});
