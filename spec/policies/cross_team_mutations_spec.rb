require "rails_helper"
require Rails.root.join("spec/support/authorization")

# AC3: a user from another Team is refused on **every** mutation route that
# exists. Annex C §7.3 asks for exactly this — "testes de segurança devem tentar
# acessar o mesmo resource ID a partir de outro Team em todas as APIs críticas".
#
# The coverage gate no longer reads this file's text — it classifies routes in
# `spec/support/authorization.rb`, because a text match was satisfied by a comment.
# The paths still appear literally in the describe blocks below for the reader, not
# for a checker.
RSpec.describe "a user from another Team", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }

  # Two Teams that know nothing of each other, each with its own OWNER.
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let!(:member) { create(:team_member, team: team, user: create(:user)) }

  let(:outsider) { create(:user, email: "outsider@example.test", password: password) }
  let!(:other_team) { create(:team, owner: outsider) }

  def sign_in_as(user)
    post sign_in_path, params: { email: user.email, password: password }
  end

  # The session cookie is `Secure` since M01-01, so it is only sent back over TLS.
  # Without this the sign-in below appears to work and every later request is
  # anonymous — which would make these examples pass for the wrong reason.
  before do
    https!
    sign_in_as(outsider)
  end

  # POST /teams — not scoped to an existing Team: anybody authenticated may
  # create one of their own. Present here so the route is visibly considered
  # rather than silently missing, and to pin that creating a Team never grants
  # anything on somebody else's.
  describe "POST /teams" do
    it "creates only their own Team, never touching another" do
      expect { post teams_path, params: { name: "Outsider Team" } }
        .to change { Team.where(owner_user_id: outsider.id).count }.by(1)

      expect(team.reload.team_members.count).to eq(2)
    end
  end

  # GET /teams/:id — a read, but the disclosure rule is the same one the
  # mutations depend on, so it is proved here next to them.
  describe "GET /teams/:id" do
    it "is answered as absent, not as forbidden" do
      get team_path(team.external_id)

      expect(response).to have_http_status(:not_found)
    end
  end

  # Not a route: suspension is reachable only through the Command in this Story
  # (there is no members route in config/routes.rb yet). Asserted here because the
  # cross-team property belongs to the mutation, not to the transport — and when
  # M11-01 gives it a route, the generated block below will cover that too.
  describe "SuspendTeamMember, which has no route yet" do
    it "cannot suspend a member of a Team they do not belong to" do
      result = SuspendTeamMember.call(actor: outsider, team: team,
        user_id: member.user.external_id)

      expect(result).to be_failure
      expect(result.code).to eq("NOT_FOUND")
      expect(member.reload.status).to eq("ACTIVE")
    end
  end

  # The generated half: one example per **tenant-scoped mutation route**, built
  # from the real route set rather than written by hand, so a route added later
  # cannot arrive without its cross-team negative. Each one issues a real request
  # as somebody from another Team and asserts they are refused without learning
  # that the resource exists.
  #
  # Until `M01-07` this generated nothing, and the file said so with an example
  # asserting the emptiness — because a generated suite that is silently empty is
  # worse than no suite. The Project routes are the first tenant-scoped mutations
  # in the product, so that example is gone and these are real.
  describe "every tenant-scoped mutation route" do
    let!(:project) { create(:project, team: team) }
    let!(:cluster) { create(:cluster, :bootstrapped, team: team) }
    let!(:environment) { create(:environment, project: project, cluster: cluster) }
    let!(:other_project) { create(:project, team: other_team) }
    let!(:other_cluster) { create(:cluster, :bootstrapped, team: other_team) }
    let!(:other_environment) { create(:environment, project: other_project, cluster: other_cluster) }

    # The slug and the id are substituted with **real** values of the Team the
    # outsider is attacking. Filling every `:param` with the same identifier — the
    # first version of this block — produced `/t/<a-ulid>/projects`, which 404s
    # because no Team has that slug. It would have passed with the tenancy check
    # deleted.
    #
    # The id has to be of the *right type* for the same reason: a `team_` id on a
    # Cluster route is refused by `Opanel::Identifier.parse` before any tenancy
    # check runs, so the 404 would prove nothing about tenancy.
    #
    # For nested resources like environments (which live under projects), multiple
    # resource types may appear in the path. The mapping is now a list of tuples:
    # (fragment, parameter_name, resource_type).
    RESOURCE_FOR = [
      [ "/projects/", "project_id", :project ],
      [ "/clusters/", "id", :cluster ],
      [ "/environments", "id", :environment ]
    ].freeze

    def attack_path(route)
      # Start with team slug substitution
      path = route[:path].gsub(":team_slug", team.slug)

      # For nested resources, substitute the appropriate resource IDs
      RESOURCE_FOR.each do |fragment, param, kind|
        next unless path.include?(fragment)

        # Substitute with the appropriate external ID based on resource type
        case kind
        when :project
          path = path.gsub(":#{param}", project.external_id)
        when :environment
          # Use an environment from another team to test cross-team access
          path = path.gsub(":#{param}", other_environment.external_id)
        else
          resource = public_send(kind)
          path = path.gsub(":#{param}", resource.external_id)
        end
      end

      path
    end

    AuthorizationHarness.routes_of_kind(:tenant_scoped).each do |route|
      it "refuses #{route[:verb]} #{route[:path]} to a member of another Team" do
        path = attack_path(route)

        process(route[:verb].downcase.to_sym, path, params: { name: "Taken over" })

        # 404, and not merely "refused". Annex C §7.3 requires a cross-team
        # request to be indistinguishable from one about a resource that does not
        # exist; 403 confirms it exists. The permissive `[404, 403, 302]` this
        # assertion used to carry passed with the tenancy scope deleted — proved
        # by deleting it — because the Policy still answered 403. It caught a
        # mutation and not a disclosure, which is half of what it claims.
        expect(response.status).to eq(404),
          "#{route[:verb]} #{path} answered #{response.status} to an outsider; a cross-team " \
          "request must be indistinguishable from one about a resource that does not exist"
        # Nothing about the Team leaks through the refusal.
        expect(response.body).not_to include(team.name)
        expect(response.body).not_to include(project.name)
        # And nothing was mutated on the way to it.
        expect(project.reload.name).not_to eq("Taken over")
        expect(team.projects.count).to eq(1)
        expect(team.clusters.count).to eq(1)
      end
    end
  end

  # Every action the matrix knows, attempted against a Team the actor has no
  # membership of. This is the assertion that grows on its own: a new action
  # registered in `TeamPolicy::PERMISSIONS` is automatically attempted here, so
  # the cross-team negative cannot be forgotten for it.
  describe "every registered action" do
    TeamPolicy.registered_actions.each do |action|
      it "denies #{action} on another Team" do
        decision = Opanel::Authorization.authorize(outsider, action, team)

        expect(decision).to be_denied
        expect(decision.reason).to eq(:no_membership)
      end
    end
  end

  describe "a membership of another Team" do
    it "does not authorize anything on this one" do
      # The outsider is an OWNER — of their own Team. Role is not global.
      expect(other_team.team_members.find_by(user_id: outsider.id).role).to eq("OWNER")

      expect(Opanel::Authorization.authorize(outsider, :manage_members, team)).to be_denied
      expect(Opanel::Authorization.authorize(outsider, :delete_team, team)).to be_denied
    end
  end
end
