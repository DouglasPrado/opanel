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
import { Field, FieldDescription, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';

interface SignUpProps {
  error?: { code: string; message: string; requestId: string } | null;
}

/**
 * Sign up.
 *
 * The password rule is stated **before** the form is submitted, not only in the
 * refusal: the Story's failure table asks for an explicit policy, and a rule a
 * user only learns by breaking it is a rule stated too late.
 */
export default function SignUp({ error = null }: SignUpProps) {
  const form = useForm({ email: '', password: '', display_name: '' });

  return (
    <>
      <Head title="Create your account" />

      <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center p-6">
        <Card>
          <CardHeader>
            <CardTitle>Create your Opanel account</CardTitle>
            <CardDescription>
              This is the identity you will operate the cluster with.
            </CardDescription>
          </CardHeader>

          <CardContent>
            {error ? (
              <Alert variant="destructive" className="mb-4" data-testid="sign-up-error">
                <AlertTitle>{error.message}</AlertTitle>
                <AlertDescription>Request {error.requestId}</AlertDescription>
              </Alert>
            ) : null}

            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.post('/sign_up');
              }}
            >
              <FieldGroup>
                <Field>
                  <FieldLabel htmlFor="display_name">Display name</FieldLabel>
                  <Input
                    id="display_name"
                    name="display_name"
                    type="text"
                    autoComplete="name"
                    required
                    value={form.data.display_name}
                    onChange={(event) => form.setData('display_name', event.target.value)}
                  />
                </Field>

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
                    autoComplete="new-password"
                    required
                    value={form.data.password}
                    onChange={(event) => form.setData('password', event.target.value)}
                  />
                  <FieldDescription>At least 12 characters.</FieldDescription>
                </Field>

                <Button type="submit" disabled={form.processing}>
                  {form.processing ? 'Creating…' : 'Create account'}
                </Button>
              </FieldGroup>
            </form>
          </CardContent>

          <CardFooter>
            <p className="text-muted-foreground text-sm">
              Already have an account? <Link href="/sign_in">Sign in</Link>
            </p>
          </CardFooter>
        </Card>
      </main>
    </>
  );
}
