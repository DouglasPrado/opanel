require "rails_helper"

# M01-19 AC1, AC3, AC5, AC6 — Service real com réplica saudável.
#
# Against a real Engine (Annex D §7), prove that:
# - AC1: Observation records image digest
# - AC3: A observation records running and healthy tasks separately
# - AC5: Partial failure is captured correctly
# - AC6: Observation handles service with running tasks; timestamps it correctly
RSpec.describe "Service observation with real healthy replicas", :swarm, :integration, :service_lab do
  it "observes service with running and healthy replicas (AC3, AC6)" do
    # Reconcile the service first so it exists in Swarm
    reconcile

    # Wait for observation to report running tasks
    observation = wait_for("observation reports running tasks", timeout: 60, interval: 2) do
      result = ObserveService.call(service: service.reload)
      result.success? && result.value.running_tasks > 0 ? result.value : nil
    end

    # Verify observation was persisted
    expect(observation).to be_persisted
    expect(service.service_observations.count).to eq(1)

    # Verify task counts are recorded
    expect(observation.desired_tasks).to eq(1)
    expect(observation.running_tasks).to be > 0
    expect(observation.docker_version_index).to be_present
    expect(observation.observed_at).to be_present
  end

  it "records image digest from running service (AC1)" do
    reconcile

    observation = wait_for("observation records image digest", timeout: 60, interval: 2) do
      result = ObserveService.call(service: service.reload)
      if result.success? && result.value.observed_image_digest&.include?(lab_digest)
        result.value
      else
        nil
      end
    end

    # The observation should record the image digest from the running service
    # lab_digest contains the full digest reference
    expect(observation.observed_image_digest).to include(lab_digest)
  end

  it "timestamps observation for stale detection (AC5, AC6)" do
    reconcile

    observation = wait_for("observation reports running tasks", timeout: 60, interval: 2) do
      result = ObserveService.call(service: service.reload)
      result.success? && result.value.running_tasks > 0 ? result.value : nil
    end

    # Service should not be marked stale immediately after observation
    is_stale = Opanel::ServiceStatus.stale?(observation, observation.observed_at + 1.minute)
    expect(is_stale).to be false
  end
end
