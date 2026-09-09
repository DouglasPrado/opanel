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

/**
 * Removes what the journeys wrote to the database.
 *
 * The E2E server runs the **test** environment, so it shares `opanel_test` with
 * RSpec — and unlike RSpec it does not run inside a rolled-back transaction. Until
 * M01-06 the journeys only read, so nothing survived them; the authenticated
 * journey registers an account and creates a Team, and those rows made 48
 * unrelated examples fail the next time the Ruby suite ran.
 *
 * Scoped by the prefixes the journeys use, never a blanket wipe: a teardown that
 * truncates everything would also destroy whatever a developer had set up by hand.
 */
function cleanJourneyRows() {
  // Ordered by the foreign keys: a Team's OWNER cannot be deleted while the Team
  // points at them (`ON DELETE RESTRICT`), and the Team a first registration
  // bootstraps is named `default-…`, not by the journey — so the Teams are found
  // through their owner rather than by slug.
  const sql = `
    CREATE TEMP TABLE journey_users AS
      SELECT id FROM users WHERE email LIKE 'panel-%' OR email LIKE 'diag-%';
    CREATE TEMP TABLE journey_teams AS
      SELECT id FROM teams WHERE owner_user_id IN (SELECT id FROM journey_users)
         OR slug LIKE 'journey-%';

    DELETE FROM audit_logs
      WHERE actor_id IN (SELECT id FROM journey_users)
         OR team_id IN (SELECT id FROM journey_teams);
    DELETE FROM instance_roles WHERE user_id IN (SELECT id FROM journey_users);
    DELETE FROM sessions WHERE user_id IN (SELECT id FROM journey_users);
    DELETE FROM team_members
      WHERE user_id IN (SELECT id FROM journey_users)
         OR team_id IN (SELECT id FROM journey_teams)
         -- invited_by is RESTRICT too: without it the first journey that invites
         -- somebody aborts the whole cleanup, and the contamination returns with
         -- nothing to point at.
         OR invited_by IN (SELECT id FROM journey_users);
    DELETE FROM teams WHERE id IN (SELECT id FROM journey_teams);
    DELETE FROM users WHERE id IN (SELECT id FROM journey_users);

    -- Only the scope the journeys create. An unqualified DELETE emptied the
    -- M01-01 lockout table wholesale, four lines under a comment promising never
    -- to do a blanket wipe, and would have discarded a login lockout a developer
    -- was in the middle of reproducing. Matching the row to its email would be
    -- narrower still and needs pgcrypto, which this database does not have — so
    -- the scope is the boundary, and login counters are left alone.
    DELETE FROM authentication_attempts WHERE scope = 'registration_ip';
  `;

  try {
    execFileSync('psql', ['-d', process.env.OPANEL_TEST_DATABASE_NAME ?? 'opanel_test', '-c', sql], {
      stdio: ['ignore', 'ignore', 'pipe'],
    });
  } catch (error) {
    // A teardown that cannot reach the database must not fail the run it is
    // cleaning up after — the journeys have already reported their result. But it
    // must be *loud*: the statements run as one transaction, so a single failure
    // leaves every row behind, and a silent one means the next Ruby suite fails
    // for a reason nobody can trace back to here.
    const detail = error instanceof Error && 'stderr' in error ? String(error.stderr).trim() : '';
    console.error(
      `e2e teardown: journey rows were NOT cleaned — the next bin/test run may fail on leftover data.\n${detail}`,
    );
  }
}

export default function globalTeardown() {
  finaliseVisualManifest();
  cleanJourneyRows();

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
