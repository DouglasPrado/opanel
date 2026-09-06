# The example page of M00-04: a Rails route rendering a React page over Inertia.
#
# No REST endpoint exists to feed this page and none should. Inertia carries the
# props; the public API exists for MCP, the CLI and external automation, and it
# shares the same Application Layer rather than being duplicated per channel
# (`docs/AGENT_RULES.md`, "Inertia and the public API").
class HomeController < ApplicationController
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
