require "rails_helper"

# Authorization for a Service against doc 04 §6.2 (AC11: audit and Policy).
RSpec.describe ServicePolicy, type: :policy do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  def context_for(role:)
    if role == "OWNER"
      { actor: team.owner, resource: service }
    else
      user = create(:user)
      create(:team_member, role: role, team: team, user: user, status: "ACTIVE")
      { actor: user, resource: service }
    end
  end

  def deny_context_for(role:)
    # Create a different team where the actor is a member (but not of the service's team)
    other_team = create(:team)
    if role == "OWNER"
      # The other team's owner tries to access this team's service
      { actor: other_team.owner, resource: service }
    else
      # A non-owner member of another team tries to access this team's service
      user = create(:user)
      create(:team_member, role: role, team: other_team, user: user, status: "ACTIVE")
      { actor: user, resource: service }
    end
  end

  describe "#view?" do
    it "grants access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be false
    end
  end

  describe "#create?" do
    let(:new_service) { Service.new(environment: environment, team: team) }

    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be false
    end
  end

  describe "#update?" do
    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end
  end
end
