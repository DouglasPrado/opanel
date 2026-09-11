import { Head, Link, useForm } from '@inertiajs/react';

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';

interface SignInProps {
  /** The error envelope of doc 09 §28, present only when the last attempt failed. */
  error?: { code: string; message: string; requestId: string } | null;
}

/**
 * Sign in.
 *
 * Deliberately not wrapped in `layouts/app-shell`: the inventory's own guidance
 * says the shell is for authenticated pages, not standalone ones, and the
 * authenticated shell arrives with M01-06.
 *
 * The form never receives a value back from the server — not the password, and
 * not the address either. Echoing the address would make the two refusals the
 * server works to keep identical distinguishable in the rendered page.
 */
export default function SignIn({ error = null }: SignInProps) {
  const form = useForm({ email: '', password: '' });

  return (
    <>
      <Head title="Sign in" />

      <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center p-6">
        <Card>
          <CardHeader>
            <CardTitle>Sign in to Opanel</CardTitle>
            <CardDescription>Use your email address and password.</CardDescription>
          </CardHeader>

          <CardContent>
            {error ? (
              <Alert variant="destructive" className="mb-4" data-testid="sign-in-error">
                <AlertTitle>{error.message}</AlertTitle>
                <AlertDescription>Request {error.requestId}</AlertDescription>
              </Alert>
            ) : null}

            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post('/sign_in');
              }}
            >
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="email">Email</FieldLabel>
                  <Input
                    id="email"
                    name="email"
                    type="email"
                    autoComplete="email"
                    required
                    value={form.data.email}
                    onChange={(event) => form.setData('email', event.target.value)}
                  />
                </Field>

                <Field>
                  <FieldLabel htmlFor="password">Password</FieldLabel>
                  <Input
                    id="password"
                    name="password"
                    type="password"
                    autoComplete="current-password"
                    required
                    value={form.data.password}
                    onChange={(event) => form.setData('password', event.target.value)}
                  />
                </Field>

                <Button type="submit" disabled={form.processing}>
                  {form.processing ? 'Signing in…' : 'Sign in'}
                </Button>
              </FieldGroup>
            </form>
          </CardContent>

          <CardFooter>
            <p className="text-muted-foreground text-sm">
              No account yet? <Link href="/sign_up">Create one</Link>
            </p>
          </CardFooter>
        </Card>
      </main>
    </>
  );
}
