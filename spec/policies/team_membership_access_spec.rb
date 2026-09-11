require "rails_helper"

# AC8 and AC10 — what a membership grants, and what it stops granting.
#
# There is no Policy class yet and there should not be one: RBAC is M01-04, and
# the only authorization rule this Story has is "an ACTIVE membership of this
# Team". It lives in `Team.accessible_to` and in `SuspendTeamMember`, and this
# file is where it is proved through a real request, because the claim is about
# *when* the loss of access takes effect — not about a method's return value.
RSpec.describe "what a team membership grants", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:member) { create(:user, email: "member@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let!(:membership) { create(:team_member, :admin, team: team, user: member) }

  def sign_in(as:)
    post sign_in_path, params: { email: as.email, password: password }, headers: modern_browser
  end

  before { https! }

  describe "suspension (AC8)" do
    it "removes access on the very next request, with the session untouched" do
      sign_in(as: member)
      get team_path(team.external_id), headers: modern_browser
      expect(response).to have_http_status(:ok)

      result = SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)
      expect(result).to be_success

      # Same browser, same cookie, no new sign-in: nothing about Team access is
      # cached anywhere, so the next request re-reads the membership and finds it
      # suspended (Annex C §7.2).
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
      expect(Session.active.where(user_id: member.id)).to exist,
        "the session itself stays valid: losing one Team is not being signed out"
    end

    it "drops the Team from the list on the next request too" do
      sign_in(as: member)
      SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)

      get teams_path, headers: modern_browser

      expect(inertia_props["teams"]).to be_empty
    end

    it "restores access when the membership becomes ACTIVE again" do
      SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)
      membership.reload.update!(status: "ACTIVE")

      sign_in(as: member)
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:ok)
    end

    it "is idempotent" do
      SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)

      expect(SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)).to be_success
      expect(membership.reload.status).to eq("SUSPENDED")
    end

    it "keeps the row, so the audit trail survives the suspension (AC9)" do
      SuspendTeamMember.call(actor: owner, team: team, user_id: member.external_id)

      expect(membership.reload).to have_attributes(status: "SUSPENDED", role: "ADMIN")
      expect(membership.joined_at).to be_present
    end
  end

  describe "an INVITED or REMOVED membership" do
    it "grants nothing before it is accepted" do
      invited = create(:user, email: "invited@example.test", password: password)
      create(:team_member, :invited, team: team, user: invited)

      sign_in(as: invited)
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end

    it "grants nothing after removal" do
      membership.update!(status: "REMOVED")

      sign_in(as: member)
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "suspending the OWNER (AC10)" do
    it "moves the Team into OWNERSHIP_RECOVERY_REQUIRED in the same transaction" do
      result = SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
        team: team, user_id: owner.external_id)

      expect(result).to be_success
      expect(team.reload.status).to eq("OWNERSHIP_RECOVERY_REQUIRED")
      expect(team.owner_membership.status).to eq("SUSPENDED")
      expect(team.owner_user_id).to eq(owner.id), "the Team still records who its owner was"
    end

    it "takes the suspended owner's access away like anybody else's" do
      SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
        team: team, user_id: owner.external_id)

      sign_in(as: owner)
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end

    it "leaves the remaining members with access to a Team in recovery" do
      SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
        team: team, user_id: owner.external_id)

      sign_in(as: member)
      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_props.dig("team", "status")).to eq("OWNERSHIP_RECOVERY_REQUIRED")
    end

    it "writes nothing at all when the transaction cannot complete" do
      allow(team).to receive(:update!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect {
        SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
          team: team, user_id: owner.external_id)
      }.to raise_error(ActiveRecord::StatementInvalid)

      expect(team.owner_membership.reload.status).to eq("ACTIVE"),
        "the membership must not be left suspended with the Team still ACTIVE"
    end
  end
end
