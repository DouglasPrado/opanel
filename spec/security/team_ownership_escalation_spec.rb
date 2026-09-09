require "rails_helper"

# "Não existe caminho para promover alguém a OWNER que não seja a transferência
# explícita de M11-03. ADMIN nunca pode criar OWNER" — the Story's Security
# Requirements, checked from the outside.
#
# Three layers have to hold independently, because each covers the others'
# failure: the database refuses the state, the domain refuses the write, and no
# route reaches the privileged path.
RSpec.describe "escalation to team ownership", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:admin) { create(:user, email: "admin@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let!(:admin_membership) { create(:team_member, :admin, team: team, user: admin) }

  describe "an ADMIN of the team" do
    it "cannot suspend the OWNER" do
      result = SuspendTeamMember.call(actor: admin, team: team, user_id: owner.external_id)

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(result.message).to match(/transfer ownership/i)
      expect(team.reload.status).to eq("ACTIVE")
      expect(team.owner_membership.status).to eq("ACTIVE")
    end

    it "cannot promote itself to OWNER through the model" do
      admin_membership.role = "OWNER"

      expect(admin_membership.save).to be(false)
      expect(admin_membership.reload.role).to eq("ADMIN")
    end

    it "is refused by the database even when the domain is bypassed" do
      expect { admin_membership.update_columns(role: "OWNER") }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_one_active_owner_per_team/)
    end
  end

  # Guarding only `update` left the claim reachable by a row *born* OWNER, and
  # the database did not catch it: while the Team waits for recovery its
  # `owner_membership_status` is SUSPENDED, so the composite foreign key is
  # satisfied by the suspended ex-OWNER. Both halves are asserted here, because a
  # fix to either one alone would leave the other side of the hole open.
  describe "a membership born OWNER" do
    let(:outsider) { create(:user, email: "outsider@example.test", password: password) }

    it "is refused by the domain on create, not only on update" do
      membership = TeamMember.new(team: team, user: outsider, role: "OWNER",
        status: "ACTIVE", joined_at: Time.current)

      expect(membership.valid?).to be(false)
      expect(membership.errors[:role].join).to match(/explicit transfer/i)
    end

    # An invitation to be OWNER is a claim that has not landed yet. Refusing it
    # only on acceptance would surface a raw unique violation to whoever accepts,
    # instead of a message to whoever invited.
    it "is refused while still only INVITED" do
      membership = TeamMember.new(team: team, user: outsider, role: "OWNER", status: "INVITED")

      expect(membership.valid?).to be(false)
      expect(membership.errors[:role].join).to match(/explicit transfer/i)
    end

    # The one birth that is not a claim: the audit trail AC9 requires to survive.
    it "still allows a REMOVED OWNER row, which is history and claims nothing" do
      membership = TeamMember.new(team: team, user: outsider, role: "OWNER",
        status: "REMOVED", joined_at: Time.current)

      expect(membership.valid?).to be(true)
    end

    it "is refused by the database on create, with the domain bypassed" do
      expect {
        TeamMember.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: team.id, user_id: outsider.id,
          role: "OWNER", status: "ACTIVE", joined_at: Time.current,
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_one_active_owner_per_team/)
    end

    context "while the team waits for ownership recovery" do
      before do
        SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
          team: team, user_id: owner.external_id)
        expect(team.reload.status).to eq("OWNERSHIP_RECOVERY_REQUIRED")
      end

      it "cannot take the team, because the suspended OWNER still holds the seat" do
        membership = TeamMember.new(team: team, user: outsider, role: "OWNER",
          status: "ACTIVE", joined_at: Time.current)

        expect(membership.valid?).to be(false)

        # In a savepoint: a constraint violation aborts the enclosing
        # transaction, and the assertions after it are the point of the example.
        expect {
          ActiveRecord::Base.transaction(requires_new: true) do
            TeamMember.insert_all!([ {
              id: Opanel::Identifier.generate, team_id: team.id, user_id: outsider.id,
              role: "OWNER", status: "ACTIVE", joined_at: Time.current,
              created_at: Time.current, updated_at: Time.current
            } ])
          end
        }.to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_one_active_owner_per_team/)

        expect(TeamMember.owners.where(team_id: team.id, status: "ACTIVE").count).to eq(0)
        expect(team.reload.owner_user_id).to eq(owner.id)
      end
    end
  end

  describe "the OWNER" do
    it "cannot suspend itself" do
      result = SuspendTeamMember.call(actor: owner, team: team, user_id: owner.external_id)

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(team.reload.owner_membership.status).to eq("ACTIVE")
    end

    it "cannot demote itself" do
      membership = team.owner_membership
      membership.role = "ADMIN"

      # The domain refuses it, and so would the composite key at COMMIT.
      expect(membership.save).to be(false)
      expect(membership.reload.role).to eq("OWNER")
    end
  end

  describe "somebody from another team" do
    let(:outsider) { create(:user, email: "outsider@example.test", password: password) }

    before { create(:team, owner: outsider) }

    it "cannot suspend a member, and is not told the member exists" do
      result = SuspendTeamMember.call(actor: outsider, team: team, user_id: admin.external_id)

      expect(result).to be_failure
      expect(result.code).to eq("NOT_FOUND")
      expect(admin_membership.reload.status).to eq("ACTIVE")
    end

    it "cannot read the team" do
      https!
      post sign_in_path, params: { email: outsider.email, password: password }, headers: modern_browser

      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a suspended member" do
    it "cannot act on the team it was suspended from" do
      admin_membership.update!(status: "SUSPENDED")

      result = SuspendTeamMember.call(actor: admin, team: team, user_id: owner.external_id)

      expect(result).to be_failure
      expect(result.code).to eq("NOT_FOUND")
    end
  end

  describe "the security procedure" do
    it "is reachable from no route in this Story" do
      # The privileged path exists for doc 04 §3.2's security suspension, and
      # nothing web-facing may reach it: INSTANCE_ADMIN is M01-03 and the
      # recovery itself is M11-04.
      routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

      expect(routes.grep(/members/)).to be_empty
      expect(routes.grep(/suspend/)).to be_empty
    end

    it "is not something a user parameter can become" do
      # `SECURITY_PROCEDURE` is a Symbol; a request parameter is a String, and
      # the comparison is `==`, so no submitted value can impersonate it.
      expect(SuspendTeamMember::SECURITY_PROCEDURE).to be_a(Symbol)
      expect(SuspendTeamMember::SECURITY_PROCEDURE.to_s == SuspendTeamMember::SECURITY_PROCEDURE).to be(false)
    end
  end

  describe "what is written about ownership" do
    it "logs the team and the actor, and no credential" do
      logs = capture_logs do
        SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
          team: team, user_id: owner.external_id)
      end

      expect(logs).to include("team.ownership.recovery_required")
      expect(logs).to include("team.member.suspended")
      expect(logs).to include(team.external_id)
      expect(logs).not_to include(password)
      expect(logs).not_to include(owner.password_digest)
    end
  end
end
