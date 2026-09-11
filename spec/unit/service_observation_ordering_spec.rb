require "rails_helper"

RSpec.describe "Service observation ordering" do
  let(:environment) { create(:environment) }
  let(:service) { create(:service, environment: environment, swarm_service_id: "abcdef0123456789abcdef0123") }

  describe "observation with higher docker_version_index does not get overwritten by older one" do
    it "rejects out-of-order observation" do
      # Create first observation with higher version index
      newer_obs = create(:service_observation,
        service: service,
        docker_version_index: 100,
        running_tasks: 1,
        healthy_tasks: 1
      )

      # Create executor that returns lower version index than what exists
      old_version_executor = FakeSwarmExecutor.new(
        "inspect_service" => [ SwarmObservations.applied(
          SwarmObservations.service_observation(
            service,
            image: "myapp:latest@sha256:abc123",
            version: 50  # Lower than existing 100
          )
        ) ],
        "list_tasks" => [ SwarmObservations.tasks(count: 1) ]
      )

      result = ObserveService.call(service: service, executor: old_version_executor)

      # ObserveService checks for out-of-order and fails gracefully.
      expect(result).to be_failure
      expect(result.code).to eq("observation_out_of_order")

      # Verify the newer observation is still there
      expect(service.service_observations.order(:docker_version_index).last).to eq(newer_obs)
    end
  end

  describe "observation with missing docker_version_index" do
    it "creates observation even without version index" do
      obs = create(:service_observation,
        service: service,
        docker_version_index: nil,
        running_tasks: 1
      )

      expect(obs).to be_persisted
      expect(obs.docker_version_index).to be_nil
    end
  end

  describe "observation ordering by observed_at" do
    it "retrieves latest observation by timestamp" do
      obs1 = create(:service_observation,
        service: service,
        running_tasks: 1,
        observed_at: 5.minutes.ago
      )

      obs2 = create(:service_observation,
        service: service,
        running_tasks: 2,
        observed_at: 2.minutes.ago
      )

      latest = service.service_observations.order(observed_at: :desc).first

      expect(latest).to eq(obs2)
      expect(latest.running_tasks).to eq(2)
    end
  end
end
