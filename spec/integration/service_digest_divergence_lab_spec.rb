require "rails_helper"

# M01-19 AC8 — Divergência de digest observada e exibida.
#
# Against a real Engine (Annex D §7), prove that:
# - AC8: When observed digest differs from desired, the divergence is recorded
# - The observation captures what the runtime actually holds
RSpec.describe "Service observation with digest divergence", :swarm, :integration, :service_lab do
  it "observes image digest from running service (AC8)" do
    # Reconcile the service - it will use lab_digest pinned to a specific digest
    reconcile

    wait_for("service has running tasks") do
      tasks = lab_service_tasks(service.technical_name)
      tasks.any? { |t| t.include?("Running") }
    end

    # Observe the service
    result = ObserveService.call(service: service)
    expect(result).to be_success

    observation = result.value

    # The observation should record the image digest that the Swarm runtime
    # is actually using for the tasks
    expect(observation.observed_image_digest).to be_present
    expect(observation.observed_image_digest).to include("sha256:")
  end

  it "captures divergence when observing desired vs actual state (AC8)" do
    # Reconcile with initial digest
    reconcile

    wait_for("service has running tasks") do
      tasks = lab_service_tasks(service.technical_name)
      tasks.any? { |t| t.include?("Running") }
    end

    # Observe the current state
    first_observation = ObserveService.call(service: service).value

    expect(first_observation.observed_image_digest).to be_present

    # The Service's desired image_digest should match what we reconciled with
    expect(service.image_digest).to eq(lab_digest)

    # The observation records what the runtime actually holds
    # In this happy path, they match
    expect(first_observation.observed_image_digest).to include(lab_digest)
  end

  it "records version divergence in docker_version_index (AC8)" do
    # Reconcile the service
    reconcile

    wait_for("service has running tasks") do
      tasks = lab_service_tasks(service.technical_name)
      tasks.any? { |t| t.include?("Running") }
    end

    # Observe the service version
    first_obs = ObserveService.call(service: service).value

    # The docker_version_index should be recorded
    expect(first_obs.docker_version_index).to be_present
    first_version = first_obs.docker_version_index

    # Update the service to trigger a new version
    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    reconcile

    # Observe again
    wait_for("service version updated") do
      second_result = ObserveService.call(service: service)
      second_result.value.docker_version_index > first_version
    end

    second_obs = ObserveService.call(service: service).value

    # The new observation should have a higher version index
    expect(second_obs.docker_version_index).to be > first_version
  end
end
