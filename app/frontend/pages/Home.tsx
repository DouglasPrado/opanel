import { useState } from 'react';
import { Head, usePage } from '@inertiajs/react';

interface HomeProps {
  /** Server-driven. The page renders what the Control Plane says, not what it remembers. */
  platform: {
    name: string;
    environment: string;
  };
  /** Present only when the server has something to report about this page. */
  error?: string | null;
}

/**
 * The example page of M00-04. It exists to prove the rendering foundation, not to
 * model anything: it shows a server prop, a piece of local UI state and an error
 * state, which are the three things every real page will need.
 *
 * Deliberately built from plain elements. The component library arrives in
 * M00-05, and the Reuse Gate applies from that point on — creating primitives
 * here would be creating exactly what is about to be imported.
 */
export default function Home({ platform, error = null }: HomeProps) {
  // Local UI state: it belongs to this page and nowhere else, so it does not go
  // near a global store (Annex I §6.4).
  const [detailsOpen, setDetailsOpen] = useState(false);
  const { requestId } = usePage().props;

  return (
    <>
      <Head title="Home" />

      <main className="mx-auto flex min-h-screen max-w-2xl flex-col justify-center gap-6 p-8">
        <header className="flex flex-col gap-1">
          <h1 className="text-3xl font-semibold tracking-tight">{platform.name}</h1>
          <p className="text-muted-foreground text-sm">Cluster-first PaaS control plane.</p>
        </header>

        {error ? (
          <div
            role="alert"
            data-testid="page-error"
            className="border-destructive/40 bg-destructive/10 text-destructive rounded-lg border px-4 py-3 text-sm"
          >
            {error}
          </div>
        ) : null}

        <section className="border-border bg-card rounded-lg border p-4">
          <button
            type="button"
            aria-expanded={detailsOpen}
            aria-controls="platform-details"
            onClick={() => setDetailsOpen((open) => !open)}
            className="text-primary text-sm font-medium underline-offset-4 hover:underline"
          >
            {detailsOpen ? 'Hide details' : 'Show details'}
          </button>

          {detailsOpen ? (
            <dl id="platform-details" className="mt-3 grid grid-cols-2 gap-2 text-sm">
              <dt className="text-muted-foreground">Environment</dt>
              <dd data-testid="platform-environment">{platform.environment}</dd>
            </dl>
          ) : null}
        </section>

        {/* Correlates what the operator sees with the server log line that produced it. */}
        <footer className="text-muted-foreground text-xs">
          Request <code data-testid="request-id">{requestId}</code>
        </footer>
      </main>
    </>
  );
}
