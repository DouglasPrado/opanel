# The example page of M00-04: a Rails route rendering a React page over Inertia.
#
# No REST endpoint exists to feed this page and none should. Inertia carries the
# props; the public API exists for MCP, the CLI and external automation, and it
# shares the same Application Layer rather than being duplicated per channel
# (`docs/AGENT_RULES.md`, "Inertia and the public API").
class HomeController < ApplicationController
  # Declared public rather than left to the default, and the reason is worth
  # writing down because the default is now "authenticated".
  #
  # This is still M00-04's example page: it renders the platform name, the
  # environment and the request id, and holds nothing belonging to anybody. The
  # authenticated shell and the real dashboard behind it are M01-06, and that is
  # the Story that should make `/` require a session.
  #
  # Making it authenticated here would also have meant editing five specs and a
  # browser journey that exercise `/` anonymously — `spec/security/
  # inertia_shared_props_spec.rb`, `spec/security/panel_headers_spec.rb`,
  # `spec/integration/observability_spec.rb`, `spec/integration/
  # job_correlation_spec.rb` and `e2e/smoke.spec.ts` — none of which is inside
  # this Story's declared boundary.
  allow_unauthenticated_access

  def show
    render inertia: "Home", props: {
      platform: {
        name: "Opanel",
        environment: Rails.env
      },
      # Surfaced only when the server actually has something to report. The page
      # renders an alert region for it; a silent failure is not a state (doc 10 §25).
      error: flash.alert
    }
  end
end
