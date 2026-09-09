import { useState } from 'react';
import { Head, router } from '@inertiajs/react';

import { SessionList, type SessionListEntry } from '@/components/features/auth';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Title } from '@/components/ui/title';

interface SessionsProps {
  /** Server-driven, and the only source of truth about what is active. */
  sessions: SessionListEntry[];
  error?: { code: string; message: string; requestId: string } | null;
}

/**
 * The user's own devices (doc 04 §8.2).
 *
 * Revocation is a server round trip and the list comes back from the server: the
 * browser never marks a row revoked on its own, because "revoked" is a fact
 * about the database and a page that decides it locally is a second source of
 * truth (Annex I §6.4).
 */
export default function Sessions({ sessions, error = null }: SessionsProps) {
  const [revokingId, setRevokingId] = useState<string | null>(null);

  return (
    <>
      <Head title="Sessions" />

      <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 p-6">
        <Title
          as="h1"
          title="Sessions"
          subtitle="Every device signed in to this account. Ending one takes effect immediately."
        />

        {error ? (
          <Alert variant="destructive" data-testid="sessions-error">
            <AlertTitle>{error.message}</AlertTitle>
            <AlertDescription>Request {error.requestId}</AlertDescription>
          </Alert>
        ) : null}

        <SessionList
          sessions={sessions}
          revokingId={revokingId}
          onRevoke={(id) => {
            setRevokingId(id);
            router.delete(`/settings/sessions/${id}`, {
              onFinish: () => setRevokingId(null),
            });
          }}
        />
      </main>
    </>
  );
}
