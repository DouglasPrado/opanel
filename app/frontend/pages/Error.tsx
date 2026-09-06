import { Head, usePage } from '@inertiajs/react'

interface ErrorProps {
  status: number
  title: string
  message: string
}

/**
 * The page every unhandled failure lands on.
 *
 * It shows the request id and nothing else about the failure. What went wrong is
 * in the server log, correlated by that id; a stack trace on screen helps an
 * attacker and not the operator (Annex C §17).
 */
export default function ErrorPage({ status, title, message }: ErrorProps) {
  const { requestId } = usePage().props

  return (
    <>
      <Head title={`${status} ${title}`} />

      <main
        role="alert"
        className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 p-8 text-center"
      >
        <p className="text-muted-foreground text-sm font-medium" data-testid="error-status">
          {status}
        </p>
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <p className="text-muted-foreground text-sm">{message}</p>

        <p className="text-muted-foreground mt-4 text-xs">
          Quote this when reporting it: <code data-testid="request-id">{requestId}</code>
        </p>
      </main>
    </>
  )
}
