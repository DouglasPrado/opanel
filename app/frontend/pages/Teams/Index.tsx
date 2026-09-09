import { Head, Link, useForm } from '@inertiajs/react';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, FieldDescription, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { Title } from '@/components/ui/title';

interface TeamEntry {
  id: string;
  name: string;
  slug: string;
  role: string;
  status: string;
  joinedAt: string | null;
}

interface TeamsIndexProps {
  /** Server-driven: only the Teams whose membership is ACTIVE ever arrive here. */
  teams: TeamEntry[];
  error?: { code: string; message: string; requestId: string } | null;
  /** A free URL name, offered when the one submitted was taken. */
  suggestion?: string | null;
}

/**
 * The Teams the signed-in user belongs to, and the form that creates one.
 *
 * Composed entirely of existing primitives — this Story ships no new component.
 * The authenticated shell is M01-06's and the product UI of a Team is M01-22's;
 * what is here is the minimum the acceptance criteria need to be exercised
 * through a real request.
 */
export default function TeamsIndex({ teams, error = null, suggestion = null }: TeamsIndexProps) {
  const form = useForm({ name: '', slug: '' });

  return (
    <>
      <Head title="Teams" />

      <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 p-6">
        <Title
          as="h1"
          title="Teams"
          subtitle="A team owns its clusters, projects and secrets. You own the one you create."
        />

        {error ? (
          <Alert variant="destructive" data-testid="teams-error">
            <AlertTitle>{error.message}</AlertTitle>
            <AlertDescription>
              {suggestion ? `Try ${suggestion}. ` : null}
              Request {error.requestId}
            </AlertDescription>
          </Alert>
        ) : null}

        <Card>
          <CardHeader>
            <CardTitle>Create a team</CardTitle>
            <CardDescription>
              You become its owner, and only a transfer can change that.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post('/teams');
              }}
            >
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="name">Name</FieldLabel>
                  <Input
                    id="name"
                    name="name"
                    type="text"
                    required
                    value={form.data.name}
                    onChange={(event) => form.setData('name', event.target.value)}
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="slug">URL name</FieldLabel>
                  <Input
                    id="slug"
                    name="slug"
                    type="text"
                    placeholder={suggestion ?? 'derived from the name'}
                    value={form.data.slug}
                    onChange={(event) => form.setData('slug', event.target.value)}
                  />
                  <FieldDescription>
                    Lowercase letters, numbers and hyphens. Left empty, it follows the name.
                  </FieldDescription>
                </Field>

                <Button type="submit" disabled={form.processing}>
                  Create team
                </Button>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>

        <ul className="flex flex-col gap-2" data-testid="team-list">
          {teams.map((team) => (
            <li key={team.id}>
              <Card>
                <CardHeader>
                  <CardTitle>
                    <Link href={`/teams/${team.id}`}>{team.name}</Link>
                  </CardTitle>
                  <CardDescription>/{team.slug}</CardDescription>
                  <Badge variant="secondary">{team.role}</Badge>
                </CardHeader>
              </Card>
            </li>
          ))}
        </ul>

        {teams.length === 0 ? (
          <p className="text-muted-foreground text-sm">You do not belong to a team yet.</p>
        ) : null}
      </main>
    </>
  );
}
