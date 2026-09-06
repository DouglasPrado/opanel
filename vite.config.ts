import { defineConfig } from 'vite'
import { fileURLToPath, URL } from 'node:url'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [RubyPlugin(), react(), tailwindcss()],
  resolve: {
    alias: {
      // `@/` is the frontend root. Server-only code is never reachable from
      // here — see the boundary rule in app/frontend/README.md, enforced by
      // lint (M00-09) and by fitness function AF-04 (M00-13).
      '@': fileURLToPath(new URL('./app/frontend', import.meta.url)),
    },
  },
})
