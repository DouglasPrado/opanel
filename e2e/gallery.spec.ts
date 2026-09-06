import { readFileSync } from 'node:fs';
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

import { galleryEntries } from '../app/frontend/components/features/gallery/registry';

/**
 * The imported component library, rendered in a real browser.
 *
 * The Vitest suite already renders every entry and fails on a console error, but
 * jsdom lays nothing out: it cannot judge contrast, focus order or keyboard
 * reachability. That is decided here (Annex B §18, doc 10 §28).
 */

interface Baseline {
  violations: Record<string, { nodes: number; why: string; fix: string; owner: string }>;
}

const baseline: Baseline = JSON.parse(readFileSync('e2e/accessibility-baseline.json', 'utf8'));

test.describe('component gallery', () => {
  test('renders every component without a browser console error', async ({ page }) => {
    const problems: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error') problems.push(message.text());
    });
    page.on('pageerror', (error) => problems.push(`pageerror: ${error.message}`));

    await page.goto('/gallery');

    await expect(page.getByRole('heading', { name: 'Component gallery' })).toBeVisible();
    await expect(page.getByTestId('gallery-ui')).toBeVisible();
    await expect(page.getByTestId('gallery-shared')).toBeVisible();
    await expect(page.getByTestId('gallery-layouts')).toBeVisible();

    // One article per inventoried component, counted from the registry so the
    // number cannot drift out of the assertion.
    await expect(page.locator('[data-testid^="gallery-entry-"]')).toHaveCount(
      galleryEntries.length,
    );

    expect(problems, `the gallery produced console errors:\n${problems.join('\n')}`).toEqual([]);
  });

  test('introduces no accessibility violation beyond the recorded upstream baseline', async ({
    page,
  }) => {
    await page.goto('/gallery');
    await expect(page.getByRole('heading', { name: 'Component gallery' })).toBeVisible();

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    const found = new Set(results.violations.map((violation) => violation.id));
    const known = new Set(Object.keys(baseline.violations));

    const introduced = results.violations.filter((violation) => !known.has(violation.id));
    const introducedSummary = introduced
      .map(
        (violation) =>
          `${violation.id} (${violation.impact}): ${violation.help}\n  ` +
          violation.nodes
            .slice(0, 5)
            .map((node) => node.target.join(' '))
            .join('\n  '),
      )
      .join('\n');

    expect(
      introduced.map((violation) => violation.id),
      `new accessibility violations:\n${introducedSummary}\n\n` +
        'Fix them. Adding to e2e/accessibility-baseline.json is only for debt that lives ' +
        'upstream in gba.dev and cannot be fixed here without redesigning an imported ' +
        'component (M00-05).',
    ).toEqual([]);

    // The baseline may only shrink. When an upstream fix lands, the entry has to
    // go — otherwise the file slowly becomes a permanent waiver.
    const fixed = [...known].filter((id) => !found.has(id));

    expect(
      fixed,
      `these baselined violations are gone — remove them from e2e/accessibility-baseline.json:\n${fixed.join('\n')}`,
    ).toEqual([]);
  });
});
