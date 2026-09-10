import { Link, router, useForm } from '@inertiajs/react';

import { EmptyState } from '@/components/shared/states';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, FieldDescription, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
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

interface TeamProp {
  id: string;
  name: string;
  slug: string;
}

interface CheckProp {
  name: string;
  status: 'PASS' | 'FAIL' | 'UNKNOWN' | 'HEALTHY' | 'DEGRADED';
  detail: string;
}

interface NodeProp {
  id: string;
  swarmNodeId: string;
  hostname: string;
  role: string;
  availability: string;
  status: string;
  advertiseAddress: string | null;
  lastSeenAt: string | null;
  stale: boolean;
}

interface ClusterProp {
  id: string;
  name: string;
  slug: string;
  status: string;
  swarmId: string | null;
  advertiseAddress: string | null;
  observedAt: string | null;
  stale: boolean;
  unreachableReason: string | null;
  operational: boolean;
  highlyAvailable: boolean;
  checks: CheckProp[];
  nodes: NodeProp[];
  permissions: { refresh: boolean };
}

interface PreflightProp {
  checks: CheckProp[];
  candidates: { name: string; address: string; private: boolean }[];
  suggested: string | null;
  choiceRequired: boolean;
  blocked: boolean;
}

interface ClustersProps {
  team: TeamProp;
  clusters: ClusterProp[];
  preflight?: PreflightProp | null;
  permissions: { bootstrap: boolean };
  error?: { code: string; message: string; requestId: string } | null;
  details?: {
    failedChecks?: { name: string; detail: string }[];
    candidates?: string[];
    cause?: string;
    adoptable?: boolean;
    swarmId?: string;
  } | null;
}

/**
 * Clusters, and the bootstrap screen of UC-003.
 *
 * ## Nothing here is carried by colour alone
 *
 * Every check prints its status as a word next to its name (doc 10 §25). A
 * greyscale screenshot in an incident report has to be readable, and so does a
 * colour-blind operator's screen.
 *
 * ## Three outcomes per check, not two
 *
 * `UNKNOWN` is rendered as itself. A check the machine could not evaluate is not
 * a check that passed, and showing it as a tick is how a bootstrap proceeds on a
 * machine nobody verified.
 *
 * ## The browser never talks to Docker
 *
 * There is no Engine address on this page and no field that accepts one. What
 * arrives is the result of checks the server ran (doc 06 §4.2, AC8).
 */
export default function Clusters({
  team,
  clusters,
  preflight = null,
  permissions,
  error = null,
  details = null,
}: ClustersProps) {
  const form = useForm({
    name: '',
    slug: '',
    advertiseAddress: preflight?.suggested ?? '',
    adoptExisting: false,
  });

  return (
    <PanelLayout section="clusters">
      <Title title="Clusters" subtitle={team.name} />

      {error ? (
        <Alert variant="destructive" className="mt-6" data-testid="clusters-error">
          <AlertTitle>{error.message}</AlertTitle>
          <AlertDescription>
            {details?.cause ? `Cause: ${details.cause}. ` : null}
            {details?.candidates?.length
              ? `Choose one of: ${details.candidates.join(', ')}. `
              : null}
            Request {error.requestId}
          </AlertDescription>
        </Alert>
      ) : null}

      {details?.failedChecks?.length ? (
        <ul className="mt-4 flex flex-col gap-1" data-testid="failed-checks">
          {details.failedChecks.map((check) => (
            <li key={check.name} className="text-sm">
              <span className="font-medium">{check.name}</span>
              <span className="text-destructive ml-2">FAIL</span>
              <span className="text-muted-foreground ml-2">{check.detail}</span>
            </li>
          ))}
        </ul>
      ) : null}

      {permissions.bootstrap ? (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Initialize a cluster</CardTitle>
            <CardDescription>
              The checks run on the server before anything is created. Nothing is initialised until
              you confirm.
            </CardDescription>
          </CardHeader>

          <CardContent className="flex flex-col gap-6">
            <Button variant="outline" data-testid="run-preflight" asChild>
              <Link href={`/t/${team.slug}/clusters/preflight`}>Run readiness checks</Link>
            </Button>

            {preflight ? (
              <ul className="flex flex-col gap-1" data-testid="preflight-checks">
                {preflight.checks.map((check) => (
                  <li key={check.name} className="text-sm" data-testid={`check-${check.name}`}>
                    <span className="font-medium">{check.name}</span>
                    {/* The status is a word. Colour is decoration on top of it. */}
                    <span
                      className={
                        check.status === 'FAIL'
                          ? 'text-destructive ml-2 font-medium'
                          : 'text-muted-foreground ml-2 font-medium'
                      }
                    >
                      {check.status}
                    </span>
                    <span className="text-muted-foreground ml-2">{check.detail}</span>
                  </li>
                ))}
              </ul>
            ) : null}

            {preflight?.blocked ? (
              <Alert variant="destructive" data-testid="preflight-blocked">
                <AlertTitle>This machine cannot host a cluster yet</AlertTitle>
                <AlertDescription>
                  Fix the checks marked FAIL above, then run them again.
                </AlertDescription>
              </Alert>
            ) : null}

            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post(`/t/${team.slug}/clusters`);
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
                  <FieldLabel htmlFor="advertiseAddress">Advertise address</FieldLabel>
                  <Input
                    id="advertiseAddress"
                    name="advertiseAddress"
                    type="text"
                    list="advertise-candidates"
                    required={preflight?.choiceRequired}
                    value={form.data.advertiseAddress}
                    onChange={(event) => form.setData('advertiseAddress', event.target.value)}
                  />
                  <datalist id="advertise-candidates">
                    {(preflight?.candidates ?? []).map((candidate) => (
                      <option key={candidate.address} value={candidate.address}>
                        {candidate.name}
                      </option>
                    ))}
                  </datalist>
                  <FieldDescription>
                    {preflight?.choiceRequired
                      ? 'This machine has several addresses. Choose the one other nodes will reach it on — it is not guessed.'
                      : 'The address other nodes will use to reach this one.'}
                  </FieldDescription>
                </Field>

                <Field orientation="horizontal">
                  <Input
                    id="adoptExisting"
                    name="adoptExisting"
                    type="checkbox"
                    className="size-4"
                    checked={form.data.adoptExisting}
                    onChange={(event) => form.setData('adoptExisting', event.target.checked)}
                  />
                  <FieldLabel htmlFor="adoptExisting">
                    Adopt the Swarm already on this machine
                  </FieldLabel>
                </Field>

                <Button type="submit" disabled={form.processing || preflight?.blocked}>
                  Initialize cluster
                </Button>
              </FieldGroup>
            </form>
          </CardContent>
        </Card>
      ) : null}

      {clusters.length === 0 ? (
        <EmptyState
          title="No clusters yet"
          description="A Cluster is the Docker Swarm your environments run on. Initialize one to get started."
          className="mt-6"
        />
      ) : (
        <ul className="mt-6 flex flex-col gap-2" data-testid="cluster-list">
          {clusters.map((cluster) => (
            <li key={cluster.id}>
              <Card>
                <CardHeader>
                  <CardTitle data-testid={`cluster-${cluster.slug}`}>{cluster.name}</CardTitle>
                  <CardDescription className="font-mono">
                    {cluster.swarmId ? `Swarm ${cluster.swarmId}` : 'no Swarm yet'}
                  </CardDescription>
                  <div className="flex flex-wrap gap-2">
                    <Badge
                      variant={cluster.status === 'READY' ? 'secondary' : 'outline'}
                      data-testid={`cluster-status-${cluster.slug}`}
                    >
                      {cluster.status}
                    </Badge>
                    {/* doc 06 §14.1: operational is not the same question as
                        highly available, and a single-node cluster is the first
                        one where the difference bites. */}
                    <Badge variant="outline">
                      {cluster.operational ? 'Operational' : 'Not operational'}
                    </Badge>
                    <Badge variant="outline">
                      {cluster.highlyAvailable ? 'HA' : 'No HA — single node'}
                    </Badge>
                  </div>
                </CardHeader>

                <CardContent className="flex flex-col gap-3">
                  {/* doc 10 §25's stale state: never a claim of health, always
                      "last observed …" with the age visible. */}
                  <p
                    className="text-muted-foreground text-sm"
                    data-testid={`observed-${cluster.slug}`}
                  >
                    {cluster.observedAt
                      ? `${cluster.stale ? 'Last observed' : 'Observed'} ${cluster.observedAt}`
                      : 'Never observed'}
                  </p>

                  {cluster.unreachableReason ? (
                    <p className="text-sm" data-testid={`reason-${cluster.slug}`}>
                      Cause: {cluster.unreachableReason}
                    </p>
                  ) : null}

                  <ul className="flex flex-col gap-1">
                    {cluster.checks.map((check) => (
                      <li key={check.name} className="text-muted-foreground text-sm">
                        <span className="font-medium">{check.name}</span>
                        <span className="ml-2">{check.status}</span>
                        <span className="ml-2">{check.detail}</span>
                      </li>
                    ))}
                  </ul>

                  {cluster.permissions.refresh ? (
                    <Button
                      variant="outline"
                      size="sm"
                      className="self-start"
                      data-testid={`refresh-${cluster.slug}`}
                      onClick={() => router.post(`/t/${team.slug}/clusters/${cluster.id}/refresh`)}
                    >
                      Take a fresh reading
                    </Button>
                  ) : null}

                  {cluster.nodes.length > 0 ? (
                    <div className="mt-4">
                      <h3 className="font-medium text-sm mb-2">Nodes</h3>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Hostname</TableHead>
                            <TableHead>Role</TableHead>
                            <TableHead>Availability</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead>Last Seen</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {cluster.nodes.map((node) => (
                            <TableRow
                              key={node.id}
                              data-testid={`node-${node.swarmNodeId}`}
                              className={node.stale ? 'opacity-60' : ''}
                            >
                              <TableCell className="text-sm">{node.hostname}</TableCell>
                              <TableCell className="text-sm">{node.role}</TableCell>
                              <TableCell className="text-sm">{node.availability}</TableCell>
                              <TableCell className="text-sm">
                                <Badge
                                  variant={
                                    node.stale
                                      ? 'outline'
                                      : node.status === 'READY'
                                        ? 'secondary'
                                        : 'destructive'
                                  }
                                  data-testid={`node-status-${node.swarmNodeId}`}
                                >
                                  {node.status}
                                </Badge>
                                {node.stale ? (
                                  <Badge variant="outline" className="ml-2">
                                    stale
                                  </Badge>
                                ) : null}
                              </TableCell>
                              <TableCell className="text-sm text-muted-foreground">
                                {node.lastSeenAt
                                  ? `${node.stale ? 'Last seen' : 'Seen'} ${node.lastSeenAt}`
                                  : 'Never'}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  ) : null}
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </PanelLayout>
  );
}
