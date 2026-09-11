require "rails_helper"

RSpec.describe NetworkPolicy, type: :policy do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster, team: team) }
  let(:network) { create(:network, environment: environment, team: team) }

  let(:admin_user) { create(:user) }
  let(:developer_user) { create(:user) }
  let(:viewer_user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:other_team) { create(:team) }

  before do
    create(:team_member, user: admin_user, team: team, role: "ADMIN", status: "ACTIVE")
    create(:team_member, user: developer_user, team: team, role: "DEVELOPER", status: "ACTIVE")
    create(:team_member, user: viewer_user, team: team, role: "VIEWER", status: "ACTIVE")
    create(:team_member, user: other_user, team: other_team, role: "ADMIN", status: "ACTIVE")
  end

  describe "#view?" do
    it "allows viewer to view network in their team" do
      policy = NetworkPolicy.new(viewer_user, network)
      expect(policy.view?).to be true
    end

    it "allows developer to view network in their team" do
      policy = NetworkPolicy.new(developer_user, network)
      expect(policy.view?).to be true
    end

    it "allows admin to view network in their team" do
      policy = NetworkPolicy.new(admin_user, network)
      expect(policy.view?).to be true
    end

    it "denies cross-team access to view" do
      policy = NetworkPolicy.new(other_user, network)
      expect(policy.view?).to be false
    end
  end

  describe "#create?" do
    it "allows admin to create network in their team" do
      policy = NetworkPolicy.new(admin_user, network)
      expect(policy.create?).to be true
    end

    it "allows developer to create network in their team" do
      policy = NetworkPolicy.new(developer_user, network)
      expect(policy.create?).to be true
    end

    it "denies viewer from creating network" do
      policy = NetworkPolicy.new(viewer_user, network)
      expect(policy.create?).to be false
    end

    it "denies cross-team network creation" do
      policy = NetworkPolicy.new(other_user, network)
      expect(policy.create?).to be false
    end
  end

  describe "#update?" do
    it "allows admin to update network in their team" do
      policy = NetworkPolicy.new(admin_user, network)
      expect(policy.update?).to be true
    end

    it "allows developer to update network in their team" do
      policy = NetworkPolicy.new(developer_user, network)
      expect(policy.update?).to be true
    end

    it "denies viewer from updating network" do
      policy = NetworkPolicy.new(viewer_user, network)
      expect(policy.update?).to be false
    end

    it "denies cross-team network update" do
      policy = NetworkPolicy.new(other_user, network)
      expect(policy.update?).to be false
    end
  end

  describe "PERMISSIONS map" do
    it "defines view permission" do
      expect(NetworkPolicy::PERMISSIONS).to have_key(:view)
    end

    it "defines create permission" do
      expect(NetworkPolicy::PERMISSIONS).to have_key(:create)
    end

    it "defines update permission" do
      expect(NetworkPolicy::PERMISSIONS).to have_key(:update)
    end
  end
end
