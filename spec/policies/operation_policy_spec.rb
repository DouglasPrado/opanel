require "rails_helper"

# Operation authorization policy with cross-team negative test.
# Every new mutation needs an authorization test, including a cross-team negative test.
RSpec.describe OperationPolicy, type: :policy do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:operation) do
    create(:operation,
      team_id: team.id,
      resource_type: "Service",
      resource_id: "svc_123"
    )
  end

  def context_for(role:)
    if role == "OWNER"
      { actor: team.owner, resource: operation }
    else
      user = create(:user)
      create(:team_member, role: role, team: team, user: user, status: "ACTIVE")
      { actor: user, resource: operation }
    end
  end

  def deny_context_for(role:)
    # Create a different team where the actor is a member (but not of the operation's team)
    other_team = create(:team)
    if role == "OWNER"
      # The other team's owner tries to access this team's operation
      { actor: other_team.owner, resource: operation }
    else
      # A non-owner member of another team tries to access this team's operation
      user = create(:user)
      create(:team_member, role: role, team: other_team, user: user, status: "ACTIVE")
      { actor: user, resource: operation }
    end
  end

  describe "#view?" do
    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(OperationPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(OperationPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(OperationPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "VIEWER")
      expect(OperationPolicy.new(ctx[:actor], ctx[:resource]).view?).to be false
    end

    it "denies an unauthenticated user" do
      expect(OperationPolicy.new(nil, operation).view?).to be false
    end
  end

  describe "tenancy enforcement" do
    it "scopes operations to the user's teams via TenantScope" do
      user = create(:user)
      create(:team_member, team: team, user: user, role: "ADMIN", status: "ACTIVE")

      scope = TenantScope.for(user, Operation).relation
      expect(scope).to include(operation)

      # Operations from other_team are not in scope
      other_team = create(:team)
      other_op = create(:operation, team_id: other_team.id)
      expect(scope).not_to include(other_op)
    end

    it "excludes operations from inactive team members" do
      user = create(:user)
      create(:team_member, team: team, user: user, role: "ADMIN", status: "SUSPENDED")

      scope = TenantScope.for(user, Operation).relation
      expect(scope).not_to include(operation)
    end
  end
end
