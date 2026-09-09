require "rails_helper"
require Rails.root.join("spec/support/authorization")

# AC10: *"existe um mecanismo que **falha o build** quando uma rota de mutação
# nova não tem teste negativo cross-team"*.
#
# This is that mechanism. It is a spec rather than a fitness function because what
# has to be proved is a property of the *route set at runtime*, which the
# application knows and a file scan does not. `bin/gate local` runs it, so a route
# added without a decision about its tenancy turns the build red.
#
# ## What the first version got wrong, and why this one is different
#
# The first version compared route paths against the **text** of the spec files.
# That is satisfied by a comment: a line reading `# TODO: cover POST /teams` made
# it green while nothing exercised the route. The review demonstrated it — feeding
# the check only the comment lines of the coverage files reported zero uncovered
# routes.
#
# Coverage is now a *classification* (`spec/support/authorization.rb`), and a route
# that matches no rule is uncovered. Deny by default, applied to the mechanism
# itself: a new route is uncovered until somebody writes down what it is, and
# writing that down is a reviewable line, not a comment anywhere in a file.
RSpec.describe "cross-team coverage of mutation routes", type: :gates do
  it "classifies every mutating route" do
    unclassified = AuthorizationHarness.unclassified_routes

    expect(unclassified).to be_empty, <<~MESSAGE
      These mutation routes are not classified:

        #{unclassified.map { |r| "#{r[:verb]} #{r[:path]}" }.join("\n  ")}

      Every mutation needs somebody from another Team attempting it and being
      refused (Annex C §7.3). Add the route to CLASSIFICATIONS in
      spec/support/authorization.rb as one of:

        :tenant_scoped — it addresses a resource owned by a Team. A cross-team
                         example is then generated for it automatically.
        :own_resource  — it touches only the caller's own rows. Name the spec that
                         proves it in the reason.
        :anonymous     — there is no actor yet.

      An exemption a reviewer can disagree with beats a silent gap; an exemption
      with no reason is a gap with better manners.
    MESSAGE
  end

  # The mechanism has to be able to fail, or it is decoration — and it has to fail
  # through **the real code path**, not through a copy of it. The earlier version
  # stubbed the route list, never called it, and asserted on a re-implementation
  # of the check inline; it would have stayed green through any breakage of the
  # thing it claimed to prove.
  it "reports a route that matches no classification" do
    invented = [ { verb: "POST", path: "/teams/:team_id/invent-something" } ]

    expect(AuthorizationHarness.unclassified_routes(invented)).to eq(invented)
  end

  it "does not report a route that is classified" do
    known = [ { verb: "POST", path: "/teams" } ]

    expect(AuthorizationHarness.unclassified_routes(known)).to be_empty
  end

  # Every classification carries a reason, so the exemption list cannot decay into
  # a list of paths somebody added to get green.
  it "gives a reason for every classification" do
    AuthorizationHarness::CLASSIFICATIONS.each do |rule|
      expect(rule[:reason]).to be_present, "#{rule[:pattern]} has no reason"
      expect(rule[:kind]).to be_in(%i[tenant_scoped own_resource anonymous])
    end
  end

  # The harness must be reading the real route set. If `mutating_routes` returned
  # nothing — a Rails upgrade changing `route.verb` from a String to a Regexp has
  # happened before — every check above would pass over an empty list.
  it "reads the real route set, and finds routes in it" do
    routes = AuthorizationHarness.mutating_routes

    expect(routes).not_to be_empty
    expect(routes.map { |r| r[:path] }).to include("/teams", "/sign_in")
    expect(routes.map { |r| r[:verb] }).to all(satisfy { |v| v != "GET" })
  end
end
