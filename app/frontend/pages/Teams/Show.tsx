import { Head, Link } from '@inertiajs/react';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Title } from '@/components/ui/title';

interface TeamsShowProps {
  team: {
    id: string;
    name: string;
    slug: string;
    status: string;
  };
}

/**
 * One Team.
 *
 * Reaching this page is itself the authorization answer: the server resolves the
 * Team through the caller's ACTIVE membership, so a suspended member gets a 404
 * on the next request rather than a page with a hidden section. The product UI
 * of a Team — members, projects, clusters — is M01-22's.
 */
export default function TeamsShow({ team }: TeamsShowProps) {
  return (
    <>
      <Head title={team.name} />

      <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 p-6">
        <Title as="h1" title={team.name} subtitle={`/${team.slug}`} />

        {team.status === 'OWNERSHIP_RECOVERY_REQUIRED' ? (
          <Alert variant="destructive" data-testid="ownership-recovery">
            <AlertTitle>This team has no active owner</AlertTitle>
            <AlertDescription>
              Its owner is suspended. An administrator has to restore ownership before ownership
              actions can be used again.
            </AlertDescription>
          </Alert>
        ) : (
          <Badge variant="secondary">{team.status}</Badge>
        )}

        <Link href="/teams" className="text-muted-foreground text-sm underline">
          All teams
        </Link>
      </main>
    </>
  );
}
