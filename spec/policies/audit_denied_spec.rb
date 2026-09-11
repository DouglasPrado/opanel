require "rails_helper"

# AC4: an authorization denial produces an audit record with `result: DENIED`.
#
# This is the detective half of M01-04's preventive control, and it also closes a
# finding that review left open — a cross-Team refusal wrote to the application
# log and to nothing queryable. A denial nobody can query is a denial nobody will
# notice happening a thousand times.
RSpec.describe "a denial is audited", type: :policy do
  let(:owner) { create(:user) }
  let(:team) { create(:team, owner: owner) }
  let(:outsider) { create(:user) }
  let!(:outsider_team) { create(:team, owner: outsider) }

  describe "an actor from another Team" do
    it "produces a DENIED record" do
      expect {
        Opanel::Authorization.authorize(outsider, :manage_members, team)
      }.to change { AuditLog.where(result: "DENIED").count }.by(1)

      entry = AuditLog.where(result: "DENIED").last

      expect(entry.action).to eq(AuditLog::ACTIONS[:authorization_denied])
      expect(entry.actor_id).to eq(outsider.id)
      expect(entry.resource_type).to eq("Team")
      expect(entry.resource_id).to eq(team.id)
    end

    it "records the classified reason, which is the whole point of the record" do
      Opanel::Authorization.authorize(outsider, :manage_members, team)

      expect(AuditLog.where(result: "DENIED").last.after["reason"]).to eq("no_membership")
    end
  end

  describe "a member whose role is insufficient" do
    it "is recorded with a different reason than an outsider" do
      viewer = create(:user)
      create(:team_member, :viewer, team: team, user: viewer)

      Opanel::Authorization.authorize(viewer, :manage_members, team)

      entry = AuditLog.where(result: "DENIED").last

      expect(entry.after["reason"]).to eq("insufficient_role")
      expect(entry.team_id).to eq(team.id)
    end
  end

  describe "an action that was allowed" do
    it "writes no denial" do
      expect {
        Opanel::Authorization.authorize(owner, :manage_members, team)
      }.not_to change { AuditLog.where(result: "DENIED").count }
    end
  end

  describe "a denial through a Command" do
    it "is audited once, from the shared path" do
      target = create(:team_member, team: team, user: create(:user))

      expect {
        SuspendTeamMember.call(actor: outsider, team: team,
          user_id: target.user.external_id)
      }.to change { AuditLog.where(result: "DENIED").count }.by(1)
    end
  end

  describe "what a denial record carries" do
    it "correlates like every other record" do
      Opanel::Authorization.authorize(outsider, :view, team)

      entry = AuditLog.where(result: "DENIED").last

      expect(entry.request_id).to be_present
      expect(entry.correlation_id).to be_present
    end

    it "carries no credential" do
      Opanel::Authorization.authorize(outsider, :delete_team, team)

      expect(AuditLog.where(result: "DENIED").last.attributes.to_json)
        .not_to include(outsider.password_digest)
    end
  end
end
