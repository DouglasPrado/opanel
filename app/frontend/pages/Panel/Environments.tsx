import { Link, useForm } from '@inertiajs/react';

import { EnvironmentBadge, type EnvironmentKind } from '@/components/shared/environment-badge';
import { EmptyState } from '@/components/shared/states';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Title } from '@/components/ui/title';
import { PanelLayout } from '@/components/layouts/panel-layout';

export const ENVIRONMENT_TYPES: EnvironmentKind[] = [
  'PRODUCTION',
  'HOMOLOGATION',
  'DEVELOPMENT',
  'PREVIEW',
  'CUSTOM',
];

const ENVIRONMENT_TYPE_LABELS: Record<EnvironmentKind, string> = {
  PRODUCTION: 'Production',
  HOMOLOGATION: 'Homologation',
  DEVELOPMENT: 'Development',
  PREVIEW: 'Preview',
  CUSTOM: 'Custom',
};

interface TeamProp {
  id: string;
  name: string;
  slug: string;
}

interface ProjectProp {
  id: string;
  name: string;
  slug: string;
}

interface ClusterOption {
  id: string;
  name: string;
  slug: string;
}

interface EnvironmentEntry {
  id: string;
  name: string;
  slug: string;
  type: EnvironmentKind;
  status: string;
  clusterName: string;
  createdAt: string | null;
}

interface EnvironmentsProps {
  team: TeamProp;
  project: ProjectProp;
  environments: EnvironmentEntry[];
  clusters: ClusterOption[];
  permissions: { create: boolean };
  error?: { code: string; message: string; requestId: string } | null;
  suggestion?: string | null;
}

/**
 * Environments of a Project: creation form and list (doc 10 UC-010, §8.1).
 *
 * Each Environment appears with a persistent badge for PRODUCTION, cluster
 * placement, derived status, and a type label. AC8 requires the PRODUCTION
 * badge to be visible and unchanging, so a reader cannot mistake which
 * Environment they are operating on during an incident.
 */
export default function Environments({
  team,
  project,
  environments,
  clusters,
  permissions,
  error = null,
  suggestion = null,
}: EnvironmentsProps) {
  const form = useForm({ name: '', slug: '', cluster_id: '', type: 'DEVELOPMENT' });

  return (
    <PanelLayout section="projects">
      <Title title="Environments" subtitle={project.name} />

      {error ? (
        <Alert variant="destructive" className="mt-6" data-testid="environments-error">
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
            <CardTitle>Create an environment</CardTitle>
            <CardDescription>
              Choose a name, type and cluster. Environments on PRODUCTION are marked persistently.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post(`/t/${team.slug}/projects/${project.id}/environments`);
              }}
            >
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="env-name">Name</FieldLabel>
                  <Input
                    id="env-name"
                    name="name"
                    value={form.data.name}
                    onChange={(e) => form.setData('name', e.target.value)}
                    placeholder="Production"
                    disabled={form.processing}
                    required
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="env-slug">URL name</FieldLabel>
                  <Input
                    id="env-slug"
                    name="slug"
                    value={form.data.slug}
                    onChange={(e) => form.setData('slug', e.target.value)}
                    placeholder="prod"
                    disabled={form.processing}
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="env-type">Type</FieldLabel>
                  <Select
                    value={form.data.type}
                    onValueChange={(value) => form.setData('type', value)}
                  >
                    <SelectTrigger id="env-type" disabled={form.processing}>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {ENVIRONMENT_TYPES.map((type) => (
                        <SelectItem key={type} value={type}>
                          {ENVIRONMENT_TYPE_LABELS[type]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>

                <Field>
                  <FieldLabel htmlFor="env-cluster">Cluster</FieldLabel>
                  <Select
                    value={form.data.cluster_id}
                    onValueChange={(value) => form.setData('cluster_id', value)}
                  >
                    <SelectTrigger id="env-cluster" disabled={form.processing}>
                      <SelectValue placeholder="Choose a cluster" />
                    </SelectTrigger>
                    <SelectContent>
                      {clusters.map((cluster) => (
                        <SelectItem key={cluster.id} value={cluster.id}>
                          {cluster.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>

                <Button type="submit" disabled={form.processing}>
                  Create environment
                </Button>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      ) : null}

      {environments.length === 0 ? (
        <EmptyState
          title="No environments yet"
          description="Create an environment to connect a Project to a Cluster."
          className="mt-12"
        />
      ) : (
        <Card className="mt-6">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Cluster</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {environments.map((env) => (
                <TableRow key={env.id} data-testid={`environment-row-${env.id}`}>
                  <TableCell>
                    <Link
                      href={`/t/${team.slug}/projects/${project.id}/environments/${env.id}`}
                      className="text-blue-600 hover:underline"
                    >
                      {env.name}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <EnvironmentBadge kind={env.type} />
                  </TableCell>
                  <TableCell>{env.clusterName}</TableCell>
                  <TableCell>{env.status}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}
    </PanelLayout>
  );
}
