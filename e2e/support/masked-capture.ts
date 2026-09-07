import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

import { test as base, expect } from '@playwright/test';

/**
 * Masking at capture, and a record of what was captured under it.
 *
 * `bin/redact-artifacts` reads bytes. A screenshot, a video and the screencast
 * frames inside a trace carry their content as *pixels*: a revealed secret, a
 * token in a field, a session id in a debug panel are all on screen and none of
 * them is a string any scanner can find. The previous check ran its patterns over
 * the container's bytes, found nothing, and published the image — which is not
 * the same as having looked at it.
 *
 * Two halves, and both are needed:
 *
 *   1. **Here.** Anything marked sensitive is covered in the page itself, before
 *      Playwright records a frame, so the pixels never contain the value.
 *   2. **In bin/redact-artifacts.** A visual artifact is published only when it
 *      appears in the manifest with a matching digest — that is, only when it came
 *      out of a context this fixture had masked. An image that appeared by any
 *      other route has no such provenance and is deleted.
 *
 * The manifest is claimed here and finalised in global-teardown.ts. It has to be
 * both: this is the only place that knows a context was masked, and Playwright
 * writes the video and the trace *after* the fixture that produced them has torn
 * down — so hashing here would vouch for the screenshot and silently omit
 * everything else.
 *
 * Appended as JSON lines: a run that is killed still leaves a truthful record of
 * what it had produced, where a single document written at the end leaves none.
 */

export const VISUAL_MANIFEST = 'tmp/test-results/visual-manifest.jsonl';

/**
 * What gets covered. Opt-in by attribute rather than by guessing at content: a
 * heuristic that tries to recognise a secret in the DOM will miss one, and a
 * missed one is published.
 *
 * `visibility: hidden` rather than a blur — a blur is reversible in principle and
 * this is the last control before the bytes leave the machine.
 */
export const REDACTION_STYLE = `
  [data-sensitive],
  [data-testid$="-secret"],
  [data-testid$="-token"],
  input[type="password"] {
    visibility: hidden !important;
  }
  [data-sensitive]::after {
    content: "[REDACTED]" !important;
    visibility: visible !important;
    display: inline-block !important;
    color: #000 !important;
    background: #000 !important;
  }
`;

function claim(entry: { path?: string; directory?: string; test: string }) {
  mkdirSync(dirname(VISUAL_MANIFEST), { recursive: true });
  appendFileSync(VISUAL_MANIFEST, `${JSON.stringify(entry)}\n`);
}

export const test = base.extend<{ maskedCapture: void }>({
  maskedCapture: [
    async ({ page }, use, testInfo) => {
      // Before the first navigation, so the very first frame the video and the
      // trace record is already masked.
      await page.addInitScript((css: string) => {
        const install = () => {
          const style = document.createElement('style');
          style.setAttribute('data-opanel-redaction', '');
          style.textContent = css;
          document.head?.appendChild(style);
        };

        if (document.head) install();
        else document.addEventListener('DOMContentLoaded', install, { once: true });
      }, REDACTION_STYLE);

      await use();

      const test = testInfo.titlePath.join(' › ');

      // Every recording this test produced. The attachments by path, and the
      // test's own output directory for the rest: Playwright finalises the video
      // and the trace after this fixture has torn down, so listing files here
      // would vouch for the screenshot and silently omit the two artifacts that
      // record the most. The directory belongs to this test alone, and this test
      // ran masked — which is the claim being made.
      for (const attachment of testInfo.attachments) {
        if (attachment.path) claim({ path: attachment.path, test });
      }

      claim({ directory: testInfo.outputDir, test });
    },
    { auto: true },
  ],
});

export { expect };
