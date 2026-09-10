import { Link, useForm } from '@inertiajs/react';

import { EmptyState } from '@/components/shared/states';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { FieldGroup, FieldLabel } from '@/components/ui/field';
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

export const SERVICE_TYPES = ['WEB', 'WORKER', 'CRON', 'TASK', 'DATABASE', 'CACHE'];

const SERVICE_TYPE_LABELS: Record<string, string> = {
  WEB: 'Web',
  WORKER: 'Worker',
  CRON: 'Cron',
  TASK: 'Task',
  DATABASE: 'Database',
  CACHE: 'Cache',
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

interface EnvironmentProp {
  id: string;
  name: string;
  slug: string;
}

interface ServiceEntry {
  id: string;
  name: string;
  slug: string;
  image_ref: string;
  service_type: string;
  replicas: number;
  status: string;
  desired_revision: number;
  applied_revision: number | null;
}

interface ServicesProps {
  team: TeamProp;
  project: ProjectProp;
  environment: EnvironmentProp;
  services: ServiceEntry[];
  permissions: { create: boolean };
  error?: { code: string; message: string; requestId: string } | null;
  suggestion?: string | null;
}

export default function Services({
  team,
  project,
  environment,
  services,
  permissions,
  error,
  suggestion,
}: ServicesProps) {
  const { data, setData, post, processing, errors } = useForm({
    name: '',
    slug: '',
    image_ref: '',
    service_type: 'WEB',
    replicas: 1,
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    post(`/t/${team.slug}/projects/${project.id}/environments/${environment.id}/services`);
  }

  return (
    <PanelLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <Title title="Services" subtitle={`in ${project.name} / ${environment.name}`} />
          {permissions.create && (
            <Button asChild variant="default">
              <Link href="#">New service</Link>
            </Button>
          )}
        </div>

        {error && (
          <Alert variant="destructive">
            <AlertTitle>{error.code}</AlertTitle>
            <AlertDescription>
              {error.message}
              {suggestion && (
                <>
                  <br />
                  {suggestion}
                </>
              )}
            </AlertDescription>
          </Alert>
        )}

        {services.length === 0 ? (
          <EmptyState title="No services" description="Create a service to get started" />
        ) : (
          <Card>
            <CardHeader>
              <CardTitle>Services</CardTitle>
              <CardDescription>
                {services.length} service{services.length !== 1 ? 's' : ''}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Image</TableHead>
                    <TableHead>Replicas</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Revision</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {services.map((service) => (
                    <TableRow key={service.id}>
                      <TableCell className="font-medium">
                        <Link
                          href={`/t/${team.slug}/projects/${project.id}/environments/${environment.id}/services/${service.id}`}
                        >
                          {service.name}
                        </Link>
                        <div className="text-xs text-gray-500">{service.slug}</div>
                      </TableCell>
                      <TableCell>
                        {SERVICE_TYPE_LABELS[service.service_type] || service.service_type}
                      </TableCell>
                      <TableCell className="text-sm text-gray-600">{service.image_ref}</TableCell>
                      <TableCell>{service.replicas}</TableCell>
                      <TableCell>
                        <span className="px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                          {service.status}
                        </span>
                      </TableCell>
                      <TableCell className="text-sm">
                        {service.applied_revision !== null
                          ? `${service.applied_revision}/${service.desired_revision}`
                          : `0/${service.desired_revision}`}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        )}

        {permissions.create && (
          <Card>
            <CardHeader>
              <CardTitle>New Service</CardTitle>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleSubmit} className="space-y-4">
                <FieldGroup>
                  <FieldLabel htmlFor="name">Name</FieldLabel>
                  <Input
                    id="name"
                    value={data.name}
                    onChange={(e) => setData('name', e.target.value)}
                    disabled={processing}
                  />
                  {errors.name && <p className="text-xs text-red-500">{errors.name}</p>}
                </FieldGroup>

                <FieldGroup>
                  <FieldLabel htmlFor="slug">Slug</FieldLabel>
                  <Input
                    id="slug"
                    value={data.slug}
                    onChange={(e) => setData('slug', e.target.value)}
                    disabled={processing}
                  />
                  {errors.slug && <p className="text-xs text-red-500">{errors.slug}</p>}
                </FieldGroup>

                <FieldGroup>
                  <FieldLabel htmlFor="image_ref">Image Reference</FieldLabel>
                  <Input
                    id="image_ref"
                    value={data.image_ref}
                    onChange={(e) => setData('image_ref', e.target.value)}
                    placeholder="myregistry/app:v1.0"
                    disabled={processing}
                  />
                  {errors.image_ref && <p className="text-xs text-red-500">{errors.image_ref}</p>}
                </FieldGroup>

                <FieldGroup>
                  <FieldLabel htmlFor="service_type">Type</FieldLabel>
                  <Select
                    value={data.service_type}
                    onValueChange={(value) => setData('service_type', value)}
                  >
                    <SelectTrigger disabled={processing}>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {SERVICE_TYPES.map((type) => (
                        <SelectItem key={type} value={type}>
                          {SERVICE_TYPE_LABELS[type]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {errors.service_type && (
                    <p className="text-xs text-red-500">{errors.service_type}</p>
                  )}
                </FieldGroup>

                <FieldGroup>
                  <FieldLabel htmlFor="replicas">Replicas</FieldLabel>
                  <Input
                    id="replicas"
                    type="number"
                    min="1"
                    value={data.replicas}
                    onChange={(e) => setData('replicas', parseInt(e.target.value) || 1)}
                    disabled={processing}
                  />
                  {errors.replicas && <p className="text-xs text-red-500">{errors.replicas}</p>}
                </FieldGroup>

                <Button type="submit" disabled={processing}>
                  Create Service
                </Button>
              </form>
            </CardContent>
          </Card>
        )}
      </div>
    </PanelLayout>
  );
}
