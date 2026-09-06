import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

/**
 * The smoke journey: the application boots, React mounts, the example page renders
 * server props and local state, and a failure renders as a page an operator can
 * act on.
 *
 * Selectors are roles, accessible names and stable test ids — never a CSS class
 * (Annex D §11.1), which lint also rejects.
 */

async function expectNoAccessibilityViolations(page: Page, context: string) {
  const results = await new AxeBuilder({ page })
    // WCAG 2.2 AA is the target (Annex B §18).
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
    .analyze();

  const summary = results.violations
    .map(
      (violation) =>
        `${violation.id} (${violation.impact}): ${violation.help} — ${violation.nodes.length} node(s)`,
    )
    .join('\n');

  expect(results.violations, `accessibility violations on ${context}:\n${summary}`).toEqual([]);
}

test.describe('smoke journey', () => {
  test('serves the application and mounts the React page', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'Opanel', level: 1 })).toBeVisible();
    await expect(page).toHaveTitle(/Opanel/);

    // The request id reaches the browser, so a user-visible failure can be
    // correlated with the server log without reproducing it.
    await expect(page.getByTestId('request-id')).not.toBeEmpty();
  });

  test('holds local UI state in the browser', async ({ page }) => {
    await page.goto('/');

    const toggle = page.getByRole('button', { name: 'Show details' });
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await expect(page.getByTestId('platform-environment')).toHaveCount(0);

    await toggle.click();

    await expect(page.getByRole('button', { name: 'Hide details' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(page.getByTestId('platform-environment')).toHaveText('test');
  });

  test('renders a failure as a page with the request id and nothing internal', async ({ page }) => {
    const response = await page.goto('/this-route-does-not-exist');

    expect(response?.status()).toBe(404);

    const alert = page.getByRole('alert');
    await expect(alert).toBeVisible();
    await expect(page.getByTestId('error-status')).toHaveText('404');
    await expect(page.getByTestId('request-id')).not.toBeEmpty();

    const body = (await page.locator('body').innerText()).toLowerCase();
    expect(body).not.toContain('traceback');
    expect(body).not.toContain('actiondispatch');
    expect(body).not.toMatch(/\/app\/controllers\//);
  });

  test('has no WCAG 2.2 AA violation on the example page', async ({ page }) => {
    await page.goto('/');
    await expectNoAccessibilityViolations(page, 'the example page');
  });

  test('has no WCAG 2.2 AA violation on the error page', async ({ page }) => {
    await page.goto('/this-route-does-not-exist');
    await expectNoAccessibilityViolations(page, 'the error page');
  });

  test('publishes no authorization or session value in the document', async ({ page }) => {
    await page.setExtraHTTPHeaders({ Authorization: 'Bearer e2e-probe-token-abc123' });
    await page.goto('/');

    const html = await page.content();
    expect(html).not.toContain('e2e-probe-token-abc123');
    expect(html).not.toContain('Bearer ');
  });
});
