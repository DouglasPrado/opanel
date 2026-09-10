require "rails_helper"

# State machine transitions: which statuses may follow which (doc 09 §17).
RSpec.describe Service, "state machine" do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  describe "valid transitions" do
    it "allows DRAFT -> PROVISIONING" do
      service.update!(status: Service::DRAFT)
      expect(service.can_transition_to?(Service::PROVISIONING)).to be true
    end

    it "allows DRAFT -> DELETING" do
      service.update!(status: Service::DRAFT)
      expect(service.can_transition_to?(Service::DELETING)).to be true
    end

    it "allows PROVISIONING -> RUNNING" do
      service.update!(status: Service::PROVISIONING)
      expect(service.can_transition_to?(Service::RUNNING)).to be true
    end

    it "allows PROVISIONING -> DEGRADED" do
      service.update!(status: Service::PROVISIONING)
      expect(service.can_transition_to?(Service::DEGRADED)).to be true
    end

    it "allows PROVISIONING -> STOPPED" do
      service.update!(status: Service::PROVISIONING)
      expect(service.can_transition_to?(Service::STOPPED)).to be true
    end

    it "allows RUNNING -> DEGRADED" do
      service.update!(status: Service::RUNNING)
      expect(service.can_transition_to?(Service::DEGRADED)).to be true
    end

    it "allows DEGRADED -> RUNNING" do
      service.update!(status: Service::DEGRADED)
      expect(service.can_transition_to?(Service::RUNNING)).to be true
    end

    it "allows STOPPED -> RUNNING" do
      service.update!(status: Service::STOPPED)
      expect(service.can_transition_to?(Service::RUNNING)).to be true
    end
  end

  describe "invalid transitions" do
    # AC5: Invalid state transitions are rejected, never "corrected" silently.
    it "forbids DRAFT -> RUNNING (must go through PROVISIONING)" do
      service.update!(status: Service::DRAFT)
      expect(service.can_transition_to?(Service::RUNNING)).to be false
    end

    it "forbids DRAFT -> DEGRADED" do
      service.update!(status: Service::DRAFT)
      expect(service.can_transition_to?(Service::DEGRADED)).to be false
    end

    it "forbids DELETING -> anything" do
      service.update!(status: Service::DELETING)
      expect(service.can_transition_to?(Service::DRAFT)).to be false
      expect(service.can_transition_to?(Service::RUNNING)).to be false
      expect(service.can_transition_to?(Service::DELETING)).to be false
    end
  end

  describe "status predicates" do
    it "draft? returns true when status is DRAFT" do
      service.update!(status: Service::DRAFT)
      expect(service.draft?).to be true
      expect(service.running?).to be false
    end

    it "running? returns true when status is RUNNING" do
      service.update!(status: Service::RUNNING)
      expect(service.running?).to be true
      expect(service.draft?).to be false
    end

    it "degraded? returns true when status is DEGRADED" do
      service.update!(status: Service::DEGRADED)
      expect(service.degraded?).to be true
    end
  end

  describe "service type predicates" do
    it "web? returns true when service_type is WEB" do
      service.update!(service_type: Service::WEB)
      expect(service.web?).to be true
      expect(service.worker?).to be false
    end

    it "worker? returns true when service_type is WORKER" do
      service.update!(service_type: Service::WORKER)
      expect(service.worker?).to be true
    end
  end
end
