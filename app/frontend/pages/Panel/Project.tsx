import { router, useForm } from '@inertiajs/react';

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

interface ProjectProp {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  status: string;
  createdAt: string | null;
  updatedAt: string | null;
}

interface ProjectPageProps {
  team: TeamProp;
  project: ProjectProp;
  /** Advisory. The server authorizes every mutation again, in its Command. */
  permissions: { update: boolean; archive: boolean };
  error?: { code: string; message: string; requestId: string } | null;
  suggestion?: string | null;
}

/**
 * One Project — the minimal `ProjectOverview` of doc 09 §23, and where UC-009
 * step 6 lands after a Project is created.
 *
 * doc 10 §7.3 calls this screen "principalmente um agregador de Environments".
 * There are no Environments yet (`M01-11`), no deployments (`M01-12`..`M01-18`)
 * and no derived health (`M01-19`), so what it aggregates today is the Project
 * itself and what this actor may do to it. Rendering those sections empty would
 * show an operator something that looks like a reading and is not one.
 *
 * No new component: `Card`, `Field`, `Input`, `Button`, `Badge` and `Alert` are
 * the imported primitives, composed.
 */
export default function ProjectPage({
  team,
  project,
  permissions,
  error = null,
  suggestion = null,
}: ProjectPageProps) {
  const form = useForm({ name: project.name, slug: project.slug });
  const path = `/t/${team.slug}/projects/${project.id}`;

  return (
    <PanelLayout section="projects">
      <Title title={project.name} subtitle={`/${project.slug}`} />

      {/* The status is a word, never only a colour (doc 10 §25). */}
      <Badge
        variant={project.status === 'ACTIVE' ? 'secondary' : 'outline'}
        className="mt-2"
        data-testid="project-status"
      >
        {project.status}
      </Badge>

      {error ? (
        <Alert variant="destructive" className="mt-6" data-testid="project-error">
          <AlertTitle>{error.message}</AlertTitle>
          <AlertDescription>
            {suggestion ? `Try ${suggestion}. ` : null}
            Request {error.requestId}
          </AlertDescription>
        </Alert>
      ) : null}

      {project.description ? (
        <p className="text-muted-foreground mt-4 text-sm" data-testid="project-description">
          {project.description}
        </p>
      ) : null}

      {permissions.update ? (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Rename</CardTitle>
            <CardDescription>
              The URL name is editable and nothing points at it — every reference uses the
              project&apos;s identifier.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.patch(path);
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
                    value={form.data.slug}
                    onChange={(event) => form.setData('slug', event.target.value)}
                  />
                  <FieldDescription>Lowercase letters, numbers and hyphens.</FieldDescription>
                </Field>

                <Button type="submit" disabled={form.processing}>
                  Save changes
                </Button>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      ) : null}

      {permissions.archive && project.status === 'ACTIVE' ? (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Archive</CardTitle>
            <CardDescription>
              An archived project keeps its data and its URL name, and stops appearing in the list.
              It cannot be edited afterwards.
            </CardDescription>
          </CardHeader>

          <CardContent>
            {/* A plain button rather than a confirmation dialog: doc 10 §26 scales
                the confirmation to the risk, and archiving destroys nothing.
                Deleting a Project — which does — is M02-09. */}
            <Button
              variant="outline"
              data-testid="project-archive"
              onClick={() => router.post(`${path}/archive`)}
            >
              Archive project
            </Button>
          </CardContent>
        </Card>
      ) : null}
    </PanelLayout>
  );
}
