import type { PageProps as InertiaPageProps } from '@inertiajs/core';

/**
 * Props every Inertia page receives, shared from the Rails side by
 * `ApplicationController#inertia_share`.
 *
 * Nothing sensitive belongs here. Shared props are serialized into the HTML of
 * every page: a token placed here is a token published to the browser. The rule
 * is asserted in spec/security/inertia_shared_props_spec.rb and will be enforced
 * by fitness function AF-06 in M00-13.
 */
export interface SharedProps {
  /** Correlates a browser action with the server log line that produced it. */
  requestId: string;
  flash: {
    notice: string | null;
    alert: string | null;
  };
}

declare module '@inertiajs/core' {
  interface PageProps extends InertiaPageProps, SharedProps {}
}
