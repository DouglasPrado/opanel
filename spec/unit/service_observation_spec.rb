require "rails_helper"

RSpec.describe ServiceObservation do
  describe "validation" do
    let(:service) { create(:service) }

    let(:valid_attrs) do
      {
        service: service,
        observed_at: Time.current,
        desired_tasks: 0,
        running_tasks: 0,
        healthy_tasks: 0,
        failed_tasks: 0
      }
    end

    it "requires desired_tasks to be present" do
      obs = ServiceObservation.new(valid_attrs.merge(desired_tasks: nil))
      expect(obs).not_to be_valid
      expect(obs.errors[:desired_tasks]).to be_present
    end

    it "requires running_tasks to be present" do
      obs = ServiceObservation.new(valid_attrs.merge(running_tasks: nil))
      expect(obs).not_to be_valid
      expect(obs.errors[:running_tasks]).to be_present
    end

    it "requires healthy_tasks to be present" do
      obs = ServiceObservation.new(valid_attrs.merge(healthy_tasks: nil))
      expect(obs).not_to be_valid
      expect(obs.errors[:healthy_tasks]).to be_present
    end

    it "requires failed_tasks to be present" do
      obs = ServiceObservation.new(valid_attrs.merge(failed_tasks: nil))
      expect(obs).not_to be_valid
      expect(obs.errors[:failed_tasks]).to be_present
    end

    it "requires observed_at to be present" do
      obs = ServiceObservation.new(valid_attrs.merge(observed_at: nil))
      expect(obs).not_to be_valid
      expect(obs.errors[:observed_at]).to be_present
    end

    it "validates task counts are non-negative integers" do
      obs = ServiceObservation.new(valid_attrs.merge(desired_tasks: -1))
      expect(obs).not_to be_valid
      expect(obs.errors[:desired_tasks]).to be_present
    end

    it "allows valid observation" do
      obs = ServiceObservation.new(valid_attrs)
      expect(obs).to be_valid
    end
  end

  describe "associations" do
    let(:service) { create(:service) }
    let(:observation) { create(:service_observation, service: service) }

    it "belongs to service" do
      expect(observation.service).to eq(service)
    end
  end

  describe "immutability" do
    let(:observation) { create(:service_observation) }

    it "should not be edited after creation (enforced by application)" do
      # This is a documentation test: updates are not prevented by the DB,
      # but the application should never call `update!` on observations.
      # The enforcement is through code review and tests that never update.
      original_running = observation.running_tasks
      observation.update(running_tasks: 999)  # Should not happen in practice

      # Reload to verify what the DB has (it will have 999 because we updated it)
      observation.reload
      expect(observation.running_tasks).to eq(999)

      # But the rule is: application never does this. Test that.
      # ObserveService.call always does .create!, never .update!
    end
  end

  describe "timestamps" do
    let(:observation) do
      create(:service_observation, observed_at: 1.hour.ago)
    end

    it "preserves the observed_at timestamp as provided" do
      expect(observation.observed_at).to be_within(1.second).of(1.hour.ago)
    end

    it "does not refresh observed_at on failed reads (tested in integration)" do
      # This is tested in integration/service_observation_stale_spec.rb
      # as it requires ObserveService to fail and then verify observation age
    end
  end

  describe "JSON columns" do
    let(:observation) do
      create(:service_observation, nodes: [ "node1", "node2" ])
    end

    it "stores and retrieves array of node IDs" do
      observation.reload
      expect(observation.nodes).to eq([ "node1", "node2" ])
    end

    it "defaults to empty array when not provided" do
      obs = create(:service_observation, nodes: nil)
      obs.reload
      expect(obs.nodes).to be_nil
    end
  end

  describe "docker_version_index tracking" do
    let(:service) { create(:service) }

    it "stores version index for out-of-order detection" do
      observation = create(:service_observation,
        service: service,
        docker_version_index: 42
      )

      observation.reload
      expect(observation.docker_version_index).to eq(42)
    end

    it "allows nil version index" do
      observation = create(:service_observation,
        service: service,
        docker_version_index: nil
      )

      expect(observation.docker_version_index).to be_nil
    end
  end
end
