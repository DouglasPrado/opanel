import { Link, useForm } from '@inertiajs/react';

import { EmptyState } from '@/components/shared/states';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, FieldDescription, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { Title } from '@/components/ui/title';
import { PanelLayout } from '@/components/layouts/panel-layout';

interface TeamProp {
  id: string;
  name: string;
  slug: string;
}

interface ProjectEntry {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  status: string;
  createdAt: string | null;
}

interface ProjectsProps {
  team: TeamProp;
  /** Server-driven, and already scoped: only this Team's Projects arrive here. */
  projects: ProjectEntry[];
  /** `null` on the last page, so the caller never compares counts. */
  nextCursor?: string | null;
  /** Advisory. The server authorizes every mutation again, in its Command. */
  permissions: { create: boolean };
  error?: { code: string; message: string; requestId: string } | null;
  /** A free URL name, offered when the one submitted was taken. */
  suggestion?: string | null;
}

/**
 * The Projects of a Team: the short flow of doc 10 §7.2 — a name, a slug, a list.
 *
 * Deliberately *not* the screen of doc 10 §7.1. Production status, environment
 * counts, last deploy and attention all need Environments, deployments and
 * derived health to exist, which is `M01-22` after `M01-19` and `M01-21`. Showing
 * those columns empty would be showing an operator something that looks like a
 * reading and is not one.
 *
 * Every element here is an existing primitive. This Story creates no component:
 * the Reuse Gate resolved to composition, and the empty state is the shared one
 * `M01-06` built rather than a fourth hand-assembled variant.
 */
export default function Projects({
  team,
  projects,
  nextCursor = null,
  permissions,
  error = null,
  suggestion = null,
}: ProjectsProps) {
  const form = useForm({ name: '', slug: '' });

  return (
    <PanelLayout section="projects">
      <Title title="Projects" subtitle={team.name} />

      {error ? (
        <Alert variant="destructive" className="mt-6" data-testid="projects-error">
          <AlertTitle>{error.message}</AlertTitle>
          <AlertDescription>
            {suggestion ? `Try ${suggestion}. ` : null}
            Request {error.requestId}
          </AlertDescription>
        </Alert>
      ) : null}

      {permissions.create ? (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Create a project</CardTitle>
            <CardDescription>
              A name and a URL name. Environments, sources and domains come after the project
              exists.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post(`/t/${team.slug}/projects`);
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
                    Lowercase letters, numbers and hyphens. Left empty, it follows the name. It is
                    editable later — nothing points at it.
                  </FieldDescription>
                </Field>

                <Button type="submit" disabled={form.processing}>
                  Create project
                </Button>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      ) : null}

      {projects.length === 0 ? (
        <EmptyState
          title="No projects yet"
          description="A Project groups the environments and services of one application. Create one to get started."
          className="mt-6"
        />
      ) : (
        <ul className="mt-6 flex flex-col gap-2" data-testid="project-list">
          {projects.map((project) => (
            <li key={project.id}>
              <Card>
                <CardHeader>
                  {/* The way back to a Project after the post-creation redirect is
                      gone. Without this the rename and archive screens are
                      reachable only by typing the URL, and the Story's own Outcome
                      — "cria, lista, renomeia e arquiva" — holds only on the first
                      visit. Review found it. */}
                  <CardTitle>
                    <Link
                      href={`/t/${team.slug}/projects/${project.id}`}
                      data-testid={`project-${project.slug}`}
                    >
                      {project.name}
                    </Link>
                  </CardTitle>
                  <CardDescription>/{project.slug}</CardDescription>
                  {/* The status is a word, never only a colour (doc 10 §25, AC7 of M01-06). */}
                  <Badge variant={project.status === 'ACTIVE' ? 'secondary' : 'outline'}>
                    {project.status}
                  </Badge>
                </CardHeader>
              </Card>
            </li>
          ))}
        </ul>
      )}

      {nextCursor ? (
        <Button variant="outline" className="mt-4" data-testid="projects-next" asChild>
          <a href={`/t/${team.slug}/projects?cursor=${nextCursor}`}>Show more</a>
        </Button>
      ) : null}
    </PanelLayout>
  );
}
