import { defineConfig, devices } from '@playwright/test';

const PORT = Number(process.env.OPANEL_E2E_PORT ?? 3999);
const BASE_URL = process.env.OPANEL_E2E_BASE_URL ?? `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: './e2e',
  outputDir: './tmp/test-results/e2e',

  // A flaky E2E is a defect with an owner and a deadline, not something to retry
  // until it passes (Annex D §20.1). One retry exists only so the report can tell
  // an infrastructure failure apart from an assertion failure — see
  // e2e/support/classified-reporter.ts, which is what actually makes that
  // distinction visible.
  retries: 1,
  forbidOnly: !!process.env.CI,
  workers: process.env.CI ? 2 : undefined,
  timeout: 30_000,
  expect: { timeout: 10_000 },

  reporter: [
    ['list'],
    ['./e2e/support/classified-reporter.ts'],
    ['json', { outputFile: 'tmp/test-results/e2e-report.json' }],
    ['html', { outputFolder: 'tmp/test-results/e2e-html', open: 'never' }],
  ],

  use: {
    baseURL: BASE_URL,
    // Diagnostics only on failure: a passing run should not archive anything, so
    // there is nothing to redact and nothing to leak.
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    // The panel is desktop-first (doc 10 §28).
    viewport: { width: 1440, height: 900 },
  },

  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],

  webServer: {
    command: `bin/rails server -p ${PORT} -e test -b 127.0.0.1`,
    // The journeys exercise what a user sees. A user sees the Inertia error page,
    // not Rails' developer page, so the E2E server renders failures the way
    // production does.
    env: { OPANEL_RENDER_ERROR_PAGES: '1' },
    url: `${BASE_URL}/up`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },

  // Failure artifacts are archived. Nothing sensitive may travel with them
  // (Annex C §17.1): the teardown scans and scrubs before anything is kept.
  globalTeardown: './e2e/support/global-teardown.ts',
});
