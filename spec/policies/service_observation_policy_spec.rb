require "rails_helper"

RSpec.describe ServiceObservationPolicy do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let(:team_a) { create(:team, owner: alice) }
  let(:team_b) { create(:team, owner: bob) }

  let(:project_a) { create(:project, team: team_a) }
  let(:project_b) { create(:project, team: team_b) }
  let(:environment_a) { create(:environment, project: project_a) }
  let(:environment_b) { create(:environment, project: project_b) }
  let(:service_a) { create(:service, environment: environment_a) }
  let(:service_b) { create(:service, environment: environment_b) }
  let(:observation_a) { create(:service_observation, service: service_a) }
  let(:observation_b) { create(:service_observation, service: service_b) }

  describe "view?" do
    context "user viewing their own team's observation" do
      let(:policy) { described_class.new(alice, observation_a) }

      it { expect(policy.view?).to be true }
    end

    context "user attempting to view another team's observation" do
      let(:policy) { described_class.new(alice, observation_b) }

      it "denies access" do
        expect(policy.view?).to be false
      end
    end

    context "unauthenticated user" do
      let(:policy) { described_class.new(nil, observation_a) }

      it "denies access" do
        expect(policy.view?).to be false
      end
    end
  end

  describe "read?" do
    context "user viewing their own team's observation" do
      let(:policy) { described_class.new(alice, observation_a) }

      it { expect(policy.read?).to be true }
    end

    context "user attempting to read another team's observation" do
      let(:policy) { described_class.new(alice, observation_b) }

      it "denies access" do
        expect(policy.read?).to be false
      end
    end
  end

  describe "AC10 compliance: cross-team negative test" do
    it "satisfies AC10 by preventing cross-team observation access" do
      # AC10: Um usuário de outro Team não lé observações, provado por teste cross-team

      # Alice creates a service in her team and observes it
      alice_observation = create(:service_observation, service: service_a)

      # Bob tries to access it
      bob_policy = ServiceObservationPolicy.new(bob, alice_observation)

      expect(bob_policy.view?).to be false
      expect(bob_policy.read?).to be false

      # Even if bob gains higher role in his own team (admin instead of owner),
      # he still can't see alice's observations
      bob_admin_team = create(:team)
      create(:team_member, team: bob_admin_team, user: bob, role: "ADMIN", status: "ACTIVE")

      expect(bob_policy.view?).to be false
    end
  end

  describe "authorization through parent Service" do
    it "delegates to ServicePolicy for the parent Service" do
      policy = described_class.new(alice, observation_a)

      # Should be true because alice can view service_a
      expect(policy.view?).to be true

      # If alice loses access to the service (membership removed), she loses access to the observation
      TeamMember.where(user: alice, team: team_a).destroy_all
      expect(policy.view?).to be false
    end
  end
end
