import { defineConfig } from 'vitest/config';
import { fileURLToPath, URL } from 'node:url';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./app/frontend', import.meta.url)),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./spec/frontend/setup.ts'],
    include: ['app/frontend/**/*.test.{ts,tsx}', 'spec/frontend/**/*.test.{ts,tsx}'],
    // The gallery imports every component, and jsdom is slower than a browser.
    testTimeout: 15_000,
    reporters: process.env.CI ? ['default', 'junit'] : ['default'],
    outputFile: { junit: 'tmp/test-results/vitest.xml' },
    css: false,
  },
});
