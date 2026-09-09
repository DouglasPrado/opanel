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
/** Identity of the signed-in operator. Never a credential — see the note above. */
export interface SharedUser {
  id: string;
  name: string;
  email: string;
}

/** A Team the operator may act in, as the switcher needs it. */
export interface SharedTeam {
  id: string;
  name: string;
  slug: string;
  role?: string;
}

export interface SharedProps {
  /** Correlates a browser action with the server log line that produced it. */
  requestId: string;
  flash: {
    notice: string | null;
    alert: string | null;
  };
  /**
   * Present on authenticated pages, absent on sign-in and sign-up. The app shell
   * needs both on every page it frames, which is what makes them shared rather
   * than per-page props.
   *
   * Deliberately narrow: an id, a display name and an address. No role list, no
   * token, no session id — anything here is published in the HTML of every
   * response (spec/security/inertia_shared_props_spec.rb).
   */
  currentUser?: SharedUser | null;
  teams?: SharedTeam[];
  currentTeam?: SharedTeam | null;
}

declare module '@inertiajs/core' {
  interface PageProps extends InertiaPageProps, SharedProps {}
}
