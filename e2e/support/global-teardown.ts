import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { VISUAL_MANIFEST } from './masked-capture';

/**
 * Redacts the failure artifacts before anyone can archive them.
 *
 * A trace, a screenshot and a video record whatever was on screen and on the
 * wire. That is exactly why they are useful, and exactly why they cannot be
 * uploaded unexamined: a token in a header or a secret in a field would be
 * published to CI storage and to anyone with the artifact link (Annex C §17.1).
 *
 * `bin/redact-artifacts` masks what it can, covers the frames inside a trace,
 * deletes what it cannot vouch for, and exits non-zero when it had to delete — so
 * a leak fails the run instead of shipping.
 */

const VISUAL = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.webm', '.mp4', '.avif'];

function filesUnder(directory: string): string[] {
  if (!existsSync(directory)) return [];

  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? filesUnder(path) : [path];
  });
}

/**
 * Turns the paths and directories masked-capture.ts claimed into digests.
 *
 * It cannot do this itself: Playwright writes the video and the trace after the
 * fixture that produced them has torn down, so a digest taken there would cover
 * the screenshot and quietly omit the two artifacts that record the most. By the
 * time this runs, every file exists.
 *
 * A claim that never produced a file is dropped rather than carried as an empty
 * entry — there is nothing to vouch for.
 */
function finaliseVisualManifest() {
  if (!existsSync(VISUAL_MANIFEST)) return;

  const digests = new Map<string, string>();

  for (const line of readFileSync(VISUAL_MANIFEST, 'utf8').split('\n')) {
    if (line.trim().length === 0) continue;

    let entry: { path?: string; directory?: string; test?: string };
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    const paths = entry.directory
      ? filesUnder(entry.directory).filter((path) =>
          VISUAL.some((extension) => path.toLowerCase().endsWith(extension)),
        )
      : entry.path
        ? [entry.path]
        : [];

    for (const path of paths) {
      if (!existsSync(path)) continue;
      digests.set(path, createHash('sha256').update(readFileSync(path)).digest('hex'));
    }
  }

  const resolved = [...digests].map(([path, sha256]) => JSON.stringify({ path, sha256 }));
  writeFileSync(VISUAL_MANIFEST, resolved.length > 0 ? `${resolved.join('\n')}\n` : '');
}

export default function globalTeardown() {
  finaliseVisualManifest();

  // Only the recordings: the trace, screenshot, video and error-context files
  // Playwright wrote, plus the JSON reports. The HTML report is generated from
  // these, so cleaning the source cleans the report — and scanning Playwright's
  // own bundled viewer would only produce false positives in minified code.
  execFileSync(
    'bin/redact-artifacts',
    [
      'tmp/test-results/e2e',
      'tmp/test-results/e2e-report.json',
      'tmp/test-results/e2e-retries.json',
    ],
    { stdio: 'inherit' },
  );
}
