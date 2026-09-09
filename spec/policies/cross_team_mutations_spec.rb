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
  # **Today it generates nothing, and that is the honest state.** An earlier
  # version of this file claimed "exactly one such route"; it was zero, and the
  # guard written to catch precisely that asserted on `mutating_routes` (all five)
  # instead of on `routes` (none) — green while its own name was false.
  #
  # There is no tenant-scoped *mutation* route yet: `POST /teams` creates a
  # resource of the caller's own, and `/teams/:id` exists only as a GET. So AC3 is
  # carried today by the Command-level and per-action examples in this file, and
  # the generated block is the mechanism waiting for M01-07's project routes.
  #
  # The emptiness is asserted rather than left implicit, so the day it stops being
  # true somebody has to come here and delete this example — at which point the
  # generated ones exist and do the work.
  describe "every tenant-scoped mutation route" do
    routes = AuthorizationHarness.routes_of_kind(:tenant_scoped)

    it "has none yet, and says so out loud" do
      expect(routes).to be_empty, <<~MESSAGE
        A tenant-scoped mutation route now exists:

          #{routes.map { |r| "#{r[:verb]} #{r[:path]}" }.join("\n  ")}

        The generated examples below now cover it. Delete this example — it exists
        only to keep "the generated suite is empty" from being silent.
      MESSAGE
    end

    routes.each do |route|
      it "refuses #{route[:verb]} #{route[:path]} to a member of another Team" do
        path = route[:path].gsub(/:\w+/) { team.external_id }

        process(route[:verb].downcase.to_sym, path)

        expect(response.status).to be_in([ 404, 403, 302 ]),
          "#{route[:verb]} #{path} answered #{response.status} to an outsider"
        expect(response.body).not_to include(team.name)
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
