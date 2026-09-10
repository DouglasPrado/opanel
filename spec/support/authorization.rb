# The harness the Story's Scope asks for: *"gera automaticamente, para cada rota
# de mutação registrada, o caso negativo cross-team"*.
#
# It exists because the alternative — remembering to write the negative for every
# new route — is the thing that fails. Enumerating the real route set means a
# route added in M01-07 shows up here without anybody deciding to add it.
#
# ## Why classification, not a text search
#
# An earlier version of the coverage gate matched route paths against the *text*
# of the spec files. That is satisfied by a comment: `# TODO: cover POST /teams`
# made the gate green while nothing exercised the route. So coverage is decided
# here, by classifying every mutating route into exactly one of three buckets, and
# the buckets are what both the generated suite and the gate read.
#
#   :tenant_scoped — addresses a resource owned by a Team. Gets a generated
#                    cross-team example that issues a real request.
#   :own_resource  — acts only on rows belonging to the caller. Covered by its own
#                    negative test, named in the reason.
#   :anonymous     — has no actor yet, so there is no "other Team" to come from.
#
# A route that matches no rule is **unclassified**, and unclassified fails the
# gate. That is the deny-by-default of this mechanism: a new route is uncovered
# until somebody says what it is.
module AuthorizationHarness
  # Ordered: the first pattern that matches decides. Each entry carries the reason
  # a reviewer would want, because an exemption without one is just a hole with
  # better manners.
  CLASSIFICATIONS = [
    {
      pattern: %r{\A/sign_up\z},
      kind: :anonymous,
      reason: "creates the actor; there is no session to come from another Team"
    },
    {
      pattern: %r{\A/sign_in\z},
      kind: :anonymous,
      reason: "authenticates; the actor does not exist yet"
    },
    {
      pattern: %r{\A/sign_out\z},
      kind: :own_resource,
      reason: "revokes only the caller's current session"
    },
    {
      pattern: %r{\A/settings/sessions},
      kind: :own_resource,
      reason: "scoped to the caller's own sessions; cross-account negative in " \
              "spec/integration/session_revocation_spec.rb"
    },
    {
      # A collection route with no resource id: anybody authenticated may create
      # one of their own, and doing so grants nothing on anybody else's.
      pattern: %r{\A/teams\z},
      kind: :own_resource,
      reason: "creates a Team owned by the caller; asserted in cross_team_mutations_spec"
    },
    {
      pattern: %r{\A/teams/:id},
      kind: :tenant_scoped,
      reason: "addresses a Team the caller may not belong to"
    },
    {
      # Create, rename and archive, all under the Team slug. The collection route
      # is tenant-scoped too, unlike `POST /teams`: creating a Project happens
      # *inside* somebody's Team, so an outsider reaching it is exactly the leak
      # this bucket exists for.
      pattern: %r{\A/t/:team_slug/projects},
      kind: :tenant_scoped,
      reason: "addresses Projects of a Team the caller may not belong to"
    }
  ].freeze

  module_function

  # Every route that changes state, from the real route set. GET is excluded
  # because AC3 and AC10 are about mutations; the read path's disclosure rule is
  # asserted separately in spec/security/authorization_disclosure_spec.rb.
  def mutating_routes
    Rails.application.routes.routes.filter_map { |route|
      verb = route.verb.to_s
      next if verb.empty? || verb == "GET"

      path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      next if path.start_with?("/rails", "/up")

      { verb: verb, path: path }
    }.uniq { |route| [ route[:verb], route[:path] ] }
  end

  def classify(path)
    CLASSIFICATIONS.find { |rule| path.match?(rule[:pattern]) }
  end

  def unclassified_routes(routes = mutating_routes)
    routes.reject { |route| classify(route[:path]) }
  end

  def routes_of_kind(kind, routes = mutating_routes)
    routes.select { |route| classify(route[:path])&.fetch(:kind) == kind }
  end
end
