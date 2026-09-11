require "rails_helper"

# AC2: an action with no registered rule is **denied**, and the omission is
# detected as a programming error rather than becoming an implicit permission.
RSpec.describe ApplicationPolicy, type: :unit do
  let(:owner) { create(:user) }
  let(:team) { create(:team, owner: owner) }

  describe "an action nobody registered" do
    it "is denied rather than allowed" do
      decision = TeamPolicy.new(owner, team).decide(:invent_a_capability)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:unregistered_action)
    end

    # Denying is the safe half. Detecting is the half AC2 asks for: a real action
    # that somebody forgot to register must not look the same as one that is
    # deliberately forbidden, or the mistake survives review.
    it "raises when asked for its roles, naming what to do" do
      expect { TeamPolicy.permitted_roles(:invent_a_capability) }
        .to raise_error(ApplicationPolicy::UnregisteredAction, /Register it in `permissions`/)
    end

    it "denies it even for the OWNER, who may do everything that is registered" do
      expect(TeamPolicy.new(owner, team).decide(:transfer_ownership)).to be_allowed
      expect(TeamPolicy.new(owner, team).decide(:transfer_ownership_somehow)).to be_denied
    end
  end

  describe "a Policy that declares nothing" do
    # The base class is the shape a new Policy starts from. If it defaulted to
    # allowing, every Policy would start life open and have to be closed.
    it "denies everything" do
      expect(described_class.permissions).to be_empty
      expect(described_class.registered_actions).to be_empty
    end
  end

  describe "the actor" do
    it "is denied when absent" do
      decision = TeamPolicy.new(nil, team).decide(:view)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:no_membership)
    end

    it "is denied when their membership is not active" do
      suspended = create(:user)
      create(:team_member, :suspended, team: team, user: suspended)

      decision = TeamPolicy.new(suspended, team).decide(:view)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:no_membership)
    end

    it "is denied when their membership was removed" do
      former = create(:user)
      create(:team_member, team: team, user: former, status: "REMOVED")

      expect(TeamPolicy.new(former, team).decide(:view)).to be_denied
    end
  end

  describe "the decision it returns" do
    it "carries what a denial has to be logged with" do
      outsider = create(:user)

      decision = TeamPolicy.new(outsider, team).decide(:manage_members)

      expect(decision.action).to eq(:manage_members)
      expect(decision.resource_type).to eq("Team")
      expect(decision.resource_id).to eq(team.external_id)
      expect(decision.team_id).to eq(team.external_id)
      expect(decision.reason).to eq(:no_membership)
    end

    it "classifies every reason it can give" do
      expect(ApplicationPolicy::REASONS.keys)
        .to match_array(%i[no_membership insufficient_role out_of_scope unregistered_action
          instance_role_required])
    end
  end

  describe "the scopes of doc 04 §6.1" do
    it "declares all six, VAULT included" do
      expect(ApplicationPolicy::SCOPES)
        .to eq(%i[team cluster project environment service vault])
    end
  end
end
