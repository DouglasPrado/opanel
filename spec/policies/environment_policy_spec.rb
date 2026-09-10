require "rails_helper"

# Authorization for Environments inside a Project inside a Team (doc 04 §6.2).
#
# Like ProjectPolicy, this answers about a resource *inside* the Team, and the
# Policy resolves the actor's membership from the resource's Team (the Environment's).
RSpec.describe EnvironmentPolicy, type: :policy do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster) }

  def context_for(role:)
    if role == "OWNER"
      { actor: team.owner, resource: environment }
    else
      user = create(:user)
      create(:team_member, role: role, team: team, user: user, status: "ACTIVE")
      { actor: user, resource: environment }
    end
  end

  def deny_context_for(role:)
    # Create a different team where the actor is a member (but not of the environment's team)
    other_team = create(:team)
    if role == "OWNER"
      # The other team's owner tries to access this team's environment
      { actor: other_team.owner, resource: environment }
    else
      # A non-owner member of another team tries to access this team's environment
      user = create(:user)
      create(:team_member, role: role, team: other_team, user: user, status: "ACTIVE")
      { actor: user, resource: environment }
    end
  end

  describe "#view?" do
    it "grants access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "OWNER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).view?).to be false
    end
  end

  describe "#create?" do
    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).create?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).create?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).create?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).create?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).create?).to be false
    end
  end

  describe "#update?" do
    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(EnvironmentPolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end
  end
end
