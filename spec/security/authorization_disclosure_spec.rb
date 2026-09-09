require "rails_helper"

# AC4: a user from another Team cannot tell "it does not exist" from "I may not
# see it".
#
# This is the criterion most easily satisfied on paper and missed in practice,
# because the two cases naturally take different code paths — one returns nil from
# a lookup, the other returns a denial — and it takes a deliberate decision to
# make them converge. So the assertions here compare the two responses to each
# other rather than checking each against an expected status.
RSpec.describe "what a denial discloses", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let(:outsider) { create(:user, email: "outsider@example.test", password: password) }
  let!(:outsider_team) { create(:team, owner: outsider) }

  before do
    https!
    post sign_in_path, params: { email: outsider.email, password: password }
  end

  # Errors are rendered the way production renders them. Rails' developer page
  # embeds the line of the spec that raised, so two refusals that are identical in
  # production differ here for a reason that has nothing to do with the
  # application — and a comparison of two developer pages would be asserting
  # against the wrong thing entirely. Same override as
  # `spec/requests/csrf_and_errors_spec.rb`.
  around do |example|
    config = Rails.application.env_config
    previous = config.values_at("action_dispatch.show_exceptions",
      "action_dispatch.show_detailed_exceptions")
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.show_detailed_exceptions"] = false

    example.run
  ensure
    config["action_dispatch.show_exceptions"] = previous[0]
    config["action_dispatch.show_detailed_exceptions"] = previous[1]
  end

  # Normalises exactly three things, and each one is unique per request **by
  # design**, so none of them can carry the fact this example is about: the id the
  # caller asked for (which they already know), the request id, and the CSRF
  # token. Anything else that differs between the two responses is a way to tell
  # "does not exist" from "not yours", and still fails the comparison.
  def normalize(body, requested_id)
    body
      .gsub(requested_id, "<requested-id>")
      .gsub(/req_[A-Za-z0-9_-]+/, "<request-id>")
      .gsub(/"requestId":"[^"]*"/, '"requestId":"<request-id>"')
      .gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "<uuid>")
      .gsub(/name="csrf-token" content="[^"]*"/, 'name="csrf-token" content="<token>"')
  end

  describe "GET /teams/:id" do
    it "answers a Team of another Team and a Team that never existed identically" do
      absent_id = Opanel::Identifier.external(:team, Opanel::Identifier.generate)

      get team_path(team.external_id)
      real_but_forbidden = [ response.status, normalize(response.body, team.external_id) ]

      get team_path(absent_id)
      never_existed = [ response.status, normalize(response.body, absent_id) ]

      # The requested id is normalised out and nothing else is: the caller already
      # knows which id they asked for, so echoing it discloses nothing — while any
      # *other* difference between the two responses would be a way to tell "yours
      # does not exist" from "this one is not yours", and still fails here.
      expect(real_but_forbidden).to eq(never_existed)
    end

    it "does not leak the name or the slug of a Team it refuses" do
      get team_path(team.external_id)

      expect(response.body).not_to include(team.name)
      expect(response.body).not_to include(team.slug)
    end
  end

  describe "DELETE /teams/:team_id/members/:id" do
    let!(:member) { create(:team_member, team: team, user: create(:user)) }

    it "answers a member of another Team and a member who never existed identically" do
      real = SuspendTeamMember.call(actor: outsider, team: team,
        user_id: member.user.external_id)

      absent = SuspendTeamMember.call(actor: outsider, team: team,
        user_id: Opanel::Identifier.external(:user, Opanel::Identifier.generate))

      expect([ real.code, real.message ]).to eq([ absent.code, absent.message ])
      expect(real.code).to eq("NOT_FOUND")
    end

    # The inverse mistake is just as bad: somebody *inside* the Team who merely
    # lacks the role must get FORBIDDEN, not NOT_FOUND — otherwise a VIEWER is
    # told the member does not exist and files a bug.
    it "says FORBIDDEN, not NOT_FOUND, to a member of the Team who lacks the role" do
      viewer = create(:user)
      create(:team_member, :viewer, team: team, user: viewer)

      result = SuspendTeamMember.call(actor: viewer, team: team,
        user_id: member.user.external_id)

      expect(result.code).to eq("FORBIDDEN")
    end
  end

  describe "what a denial writes to the log" do
    it "records the actor, action, resource and classified reason" do
      logs = capture_logs do
        Opanel::Authorization.authorize(outsider, :manage_members, team)
      end

      expect(logs).to include("authorization.denied")
      expect(logs).to include("manage_members")
      expect(logs).to include("no_membership")
      expect(logs).to include(outsider.external_id)
    end

    it "writes nothing when the action is allowed" do
      logs = capture_logs do
        Opanel::Authorization.authorize(owner, :view, team)
      end

      expect(logs).not_to include("authorization.denied")
    end

    it "carries no credential" do
      logs = capture_logs do
        Opanel::Authorization.authorize(outsider, :delete_team, team)
      end

      expect(logs).not_to include(password)
      expect(logs).not_to include(outsider.password_digest)
    end
  end
end
