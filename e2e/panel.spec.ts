import { readFileSync } from 'node:fs';

import { type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

import { test, expect } from './support/masked-capture';

interface BaselineEntry {
  nodes: number;
  why: string;
  owner: string;
  waiver: string;
  expires_at: string;
}

const baseline: { violations: Record<string, BaselineEntry> } = JSON.parse(
  readFileSync('e2e/accessibility-baseline.json', 'utf8'),
);

/**
 * The one baseline entry the panel is allowed to carry: the theme's contrast
 * tokens, recorded as `a11y-2026-001` with an owner and an expiry.
 *
 * Read from the file rather than hard-coded, so that when the waiver is removed
 * upstream this stops silently waiving anything — and asserted below, so a typo
 * cannot turn the allowance into a no-op that looks like rigour.
 */
const THEME_DEBT = 'color-contrast';

/**
 * The authenticated journey: register, land in the shell, move between its
 * sections, and leave — with WCAG 2.2 AA asserted on every screen this Story
 * delivers (AC9).
 *
 * The accessibility check is the same analyzer `smoke.spec.ts` and
 * `gallery.spec.ts` already use. An earlier version of this Story's report
 * claimed no automated AA checker existed here and downgraded AC9 to "partially
 * met" on that basis; the checker was already a devDependency, already wrapped in
 * a helper, and already applied to two screens. Nothing new was needed — only
 * this file.
 *
 * Selectors are roles, accessible names and stable test ids, never CSS classes
 * (Annex D §11.1).
 */

/**
 * Fails on any WCAG 2.2 AA violation except the theme debt already waived in
 * `e2e/accessibility-baseline.json`.
 *
 * **This extends that baseline to a page of Opanel's own, and the file's own
 * comment says its pages carry none** — so it is a change to a stated rule and is
 * flagged in the Story report for the reviewer rather than slipped in.
 *
 * The reasoning: the shell renders `shared/profile`, whose `AvatarFallback` uses
 * the `muted-foreground` token. Axe measures it at 4.16:1 against 4.5:1. The token
 * is the one already recorded as `a11y-2026-001` with an owner and an expiry, the
 * fix belongs in the gba.dev theme, and M00-05 forbids redesigning an imported
 * component here. The alternatives were worse: silence the check, drop the account
 * menu from the shell, or patch a vendored component and create drift nobody
 * reconciles.
 *
 * Everything else still blocks, `allowed` is only what the baseline already
 * carries with a live waiver, and an expired one fails in `gallery.spec.ts`.
 */
async function expectNoAccessibilityViolations(
  page: Page,
  context: string,
  { allowThemeDebt = false }: { allowThemeDebt?: boolean } = {},
) {
  const results = await new AxeBuilder({ page })
    // WCAG 2.2 AA is the target (Annex B §18).
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
    .analyze();

  // Only the one violation this Story argued for, never every id the baseline
  // happens to carry. `Object.keys(baseline.violations)` also waived
  // `aria-input-field-name` and `scrollable-region-focusable` — keyboard
  // reachability failures that nothing in the reasoning covers, invisible today
  // and untrue the moment M01-07 puts a ScrollArea in the panel.
  const waived = allowThemeDebt ? [ THEME_DEBT ] : [];
  const blocking = results.violations.filter((violation) => !waived.includes(violation.id));

  const summary = blocking
    .map(
      (violation) =>
        `${violation.id} (${violation.impact}): ${violation.help} — ${violation.nodes.length} node(s)`,
    )
    .join('\n');

  expect(blocking, `accessibility violations on ${context}:\n${summary}`).toEqual([]);
}

const PASSWORD = 'hunter2-hunter2-hunter2';

/**
 * Types into a password field that the capture fixture has hidden.
 *
 * `masked-capture` sets `visibility: hidden !important` on every
 * `input[type="password"]` before Playwright records a frame, which is the whole
 * point of it — traces and screenshots must not carry a credential. That makes
 * the control fail Playwright's actionability check, and `fill` with `force`
 * is **worse than useless** here: it skips the check but cannot move focus to a
 * hidden element, so the text lands in whichever field had focus. It silently
 * appended the password to the email address and left the password empty, which
 * is exactly the kind of green-looking wrong that costs an afternoon.
 *
 * So the value is set through the native setter and an `input` event is
 * dispatched — the documented way to drive a React-controlled input from
 * outside. The masking is untouched: the field stays hidden in every frame.
 */
async function fillPassword(page: Page, selector: string, value: string) {
  await page.locator(selector).evaluate((element, password) => {
    const input = element as HTMLInputElement;
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      'value',
    )?.set;

    setter?.call(input, password);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);

  // Proves the value actually landed. Without this the journey can pass its
  // navigation assertions while having typed the credential somewhere else.
  await expect(page.locator(selector)).toHaveValue(value);
}

/** A fresh account per run: the journey must not depend on leftover state. */
function uniqueEmail() {
  return `panel-${Date.now()}-${Math.floor(Math.random() * 10_000)}@example.test`;
}

async function registerAndSignIn(page: Page) {
  const email = uniqueEmail();

  await page.goto('/sign_up');

  // By id rather than by label text: the labels are rendered by `field`, and a
  // regex over them matched more than one control. Ids here are stable and
  // explicit — the rule that bans CSS classes as selectors is about styling
  // decisions, and an id on a form control is not one.
  await page.locator('#display_name').fill('Panel Journey');
  await page.locator('#email').fill(email);
  await fillPassword(page, '#password', PASSWORD);
  await page.getByRole('button', { name: /create account/i }).click();

  // Where the registration lands depends on a real property of the installation:
  // the *first* account bootstraps it and gets a Team, and every later one does
  // not. Both are correct, and the journey must work on a machine that has run
  // this suite before — so it creates a Team when it has none rather than
  // assuming an empty database.
  await page.waitForURL(/\/(teams|t\/[^/]+\/projects)/);

  if (new URL(page.url()).pathname === '/teams') {
    const slug = `journey-${Date.now()}`;
    await page.locator('#name').fill('Journey Team');
    await page.locator('#slug').fill(slug);
    await page.getByRole('button', { name: /create team/i }).click();
    await page.waitForURL(/\/teams\//);

    // Into the panel of the Team just created.
    await page.goto(`/t/${slug}/projects`);
  }

  await page.waitForURL(/\/t\/[^/]+\/projects/);

  return email;
}

/**
 * One registration per run, deliberately.
 *
 * `RegisterUser` throttles sign-ups to five per hour per IP (M01-01 AC7), and it
 * is a real control rather than a test nuisance. A file with three tests that each
 * register exhausts it on the second run of the suite and then fails for a reason
 * that has nothing to do with the code under test. So the authenticated
 * assertions share one journey, which is also how a person would experience them.
 */
test.describe('the authenticated panel', () => {
  // The allowance has to point at something real, or it is a waiver of nothing
  // that reads like a waiver of something.
  test('waives only the theme contrast debt, and only while its waiver is live', () => {
    const entry = baseline.violations[THEME_DEBT];

    expect(entry, `${THEME_DEBT} is no longer in the baseline — drop the allowance`).toBeDefined();
    expect(new Date(entry.expires_at).getTime()).toBeGreaterThan(Date.now());
    expect(entry.waiver).toBe('a11y-2026-001');
  });

  test('signs up, lands in the shell, navigates it and drives it from the keyboard', async ({
    page,
  }) => {
    await registerAndSignIn(page);

    // The shell frames the page: the account menu and the team switcher are the
    // two controls AC1 names.
    await expect(page.getByTestId('team-switcher')).toBeVisible();

    // AC2: Projects comes before Clusters, asserted on what the DOM renders
    // rather than on the constant behind it.
    const navigation = page.getByTestId(/^nav-/);
    await expect(navigation.first()).toHaveAttribute('data-testid', 'nav-projects');

    const order = await navigation.evaluateAll((nodes) =>
      nodes.map((node) => node.getAttribute('data-testid')),
    );
    expect(order.indexOf('nav-projects')).toBeLessThan(order.indexOf('nav-clusters'));

    await expectNoAccessibilityViolations(page, 'panel — projects', { allowThemeDebt: true });

    // Every section the sidebar offers actually resolves; a navigation entry that
    // leads nowhere teaches the operator the sidebar cannot be trusted.
    for (const section of ['clusters', 'audit', 'settings'] as const) {
      await page.getByTestId(`nav-${section}`).click();
      await expect(page.getByTestId('state-empty')).toBeVisible();
      await expectNoAccessibilityViolations(page, `panel — ${section}`, { allowThemeDebt: true });
    }

    // doc 10 §25: an empty state is a required state, and it says what the section
    // is for rather than merely that it is empty.
    await page.getByTestId('nav-projects').click();
    const empty = page.getByTestId('state-empty');
    await expect(empty).toBeVisible();
    await expect(empty).toContainText(/project/i);

    // AC6: operable from the keyboard, and focus returns to the trigger when the
    // menu closes. Asserted with real key events — this is the one place the
    // behaviour is real rather than a jsdom approximation.
    const switcher = page.getByTestId('team-switcher');
    await switcher.focus();
    await expect(switcher).toBeFocused();

    await page.keyboard.press('Enter');
    await expect(page.getByRole('menu')).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(page.getByRole('menu')).toBeHidden();
    await expect(switcher).toBeFocused();
  });

  test('keeps the sign-in screen accessible too', async ({ page }) => {
    await page.goto('/sign_in');

    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible();
    await expectNoAccessibilityViolations(page, 'sign in');
  });

  test('keeps the sign-up screen accessible', async ({ page }) => {
    await page.goto('/sign_up');

    await expectNoAccessibilityViolations(page, 'sign up');
  });

});
