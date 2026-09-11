# ObserveService reads actual state from Swarm and persists it as ServiceObservation.
#
# This is called by the periodic sweep job (ObserveServicesJob). It records
# task counts, health, image digest and timestamps — everything needed to derive
# Service status without a stored boolean.
#
# If observation fails (Executor unavailable), the previous observation is preserved
# with its original age — not refreshed. This way a stale observation stays stale
# and does not trick the status derivation into showing HEALTHY.
#
# Observations arriving out of order (lower docker_version_index) do not overwrite
# newer ones.
class ObserveService
  def self.call(service:, executor: nil)
    new(service, executor: executor).call
  end

  def initialize(service, executor: nil)
    @service = service
    @executor = executor || SwarmExecutor.new
  end

  def call
    service_id = @service.id
    swarm_service_id = @service.swarm_service_id

    # If Service has not converged yet, there is no Swarm resource to observe.
    if swarm_service_id.nil?
      return Opanel::Result.failure(
        code: "service_not_yet_provisioned",
        message: "Service has not converged to Swarm yet"
      )
    end

    # Read actual state from Swarm Executor.
    observation_data = read_observation_from_executor(swarm_service_id)

    if observation_data.nil?
      return Opanel::Result.failure(
        code: "observation_failed",
        message: "Could not read Service state from Swarm"
      )
    end

    # Check for out-of-order observation: do not overwrite newer docker_version_index.
    if newer_observation_exists?(service_id, observation_data[:docker_version_index])
      return Opanel::Result.failure(
        code: "observation_out_of_order",
        message: "Newer observation already recorded"
      )
    end

    # Persist the observation as immutable append-only record.
    observation = ServiceObservation.create!(
      service_id: service_id,
      swarm_service_id: swarm_service_id,
      desired_tasks: observation_data[:desired_tasks],
      running_tasks: observation_data[:running_tasks],
      healthy_tasks: observation_data[:healthy_tasks],
      failed_tasks: observation_data[:failed_tasks],
      observed_image_digest: observation_data[:observed_image_digest],
      update_status: observation_data[:update_status],
      nodes: observation_data[:nodes],
      docker_version_index: observation_data[:docker_version_index],
      observed_at: observation_data[:observed_at]
    )

    Opanel::Result.success(observation)
  rescue StandardError => e
    Opanel::Result.failure(
      code: "observation_error",
      message: "Failed to observe Service: #{e.message}"
    )
  end

  private

  # Reads observation from SwarmExecutor via ExecutorCommand.
  # Returns nil if the executor is unavailable.
  def read_observation_from_executor(swarm_service_id)
    # Inspect the service to get its spec and current version
    inspect_result = @executor.execute(
      ExecutorCommand.new(
        id: Opanel::Identifier.external(:operation, Opanel::Identifier.generate),
        type: "inspect_service",
        cluster_id: @service.environment.cluster_id,
        resource_type: "Service",
        resource_id: @service.external_id,
        correlation_id: Current.correlation_id.presence || SecureRandom.uuid
      )
    )

    return nil unless inspect_result&.applied?

    service_data = inspect_result.observed&.attributes
    return nil if service_data.nil?

    # Get task list for the service
    tasks_result = @executor.execute(
      ExecutorCommand.new(
        id: Opanel::Identifier.external(:operation, Opanel::Identifier.generate),
        type: "list_tasks",
        cluster_id: @service.environment.cluster_id,
        resource_type: "Service",
        resource_id: @service.external_id,
        correlation_id: Current.correlation_id.presence || SecureRandom.uuid
      )
    )

    return nil unless tasks_result&.applied?

    # The executor already filters tasks via current_tasks; we use the counts
    running_count = tasks_result.safe_metadata.fetch("states", {}).fetch("running", 0)
    healthy_count = count_healthy_tasks_from_result(tasks_result)
    failed_count = tasks_result.safe_metadata.fetch("states", {}).fetch("failed", 0)

    {
      desired_tasks: service_data.fetch("replicas", 0),
      running_tasks: running_count,
      healthy_tasks: healthy_count,
      failed_tasks: failed_count,
      observed_image_digest: service_data.fetch("image", nil),
      update_status: @service.reload.status, # TODO: derive from service_data when available
      nodes: [], # TODO: extract from task list when available
      docker_version_index: inspect_result.observed_runtime_version,
      observed_at: Time.current
    }
  end

  # Counts healthy tasks from executor result (in M01 this is simplified).
  # In M02-04 this expands to include probe-based health.
  def count_healthy_tasks_from_result(tasks_result)
    # For now, count running as a proxy for healthy
    tasks_result.safe_metadata.fetch("states", {}).fetch("running", 0)
  end

  # Checks if a newer observation already exists for this service.
  def newer_observation_exists?(service_id, new_version_index)
    return false if new_version_index.nil?

    latest_obs = ServiceObservation
      .where(service_id: service_id)
      .order(docker_version_index: :desc)
      .first

    return false if latest_obs.nil? || latest_obs.docker_version_index.nil?

    latest_obs.docker_version_index > new_version_index
  end
end
