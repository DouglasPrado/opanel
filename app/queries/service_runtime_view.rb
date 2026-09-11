# A view of a Service's runtime state (doc 10 UC-013, doc 09 §23).
#
# This query returns both desired state (from the Service table) and actual state
# (from ServiceObservation). It also derives the presented status from appliedRevision
# and observation, showing both sides of convergence explicitly (doc 03 §2.1).
#
# Status is never stored as a boolean; it is always derived. Staleness is marked so
# the UI can show "last observed X seconds ago" and avoid declaring HEALTHY without
# fresh data (doc 10 §25).
#
class ServiceRuntimeView
  def self.call(actor:, service:)
    new(actor: actor, service: service).call
  end

  def initialize(actor:, service:)
    @actor = actor
    @service = service
  end

  def call
    return Opanel::Result.failure(code: "NOT_FOUND", message: "Service not found") if service.nil?

    # Authorization check (view is the minimal permission).
    policy = ServicePolicy.new(actor, service)
    unless policy.view?
      return Opanel::Result.failure(
        code: "FORBIDDEN",
        message: ApplicationPolicy::REASONS[:insufficient_role]
      )
    end

    # Get the latest observation (actual state).
    latest_observation = service.service_observations.order(observed_at: :desc).first

    # Derive the presented status from applied revision and observation.
    presented_status = Opanel::ServiceStatus.derive(
      desired_revision: service.desired_revision,
      applied_revision: service.applied_revision,
      observation: latest_observation,
      observed_at_timestamp: Time.current
    )

    # Calculate observation staleness.
    observation_stale = Opanel::ServiceStatus.stale?(latest_observation, Time.current)
    observation_age_seconds = latest_observation ? (Time.current - latest_observation.observed_at).to_i : nil

    # Combine desired and actual state with explicit visibility.
    data = {
      id: service.external_id,
      environment_id: service.environment.external_id,
      name: service.name,
      slug: service.slug,
      service_type: service.service_type,

      # Desired state (user configuration)
      desired: {
        image_ref: service.image_ref,
        image_digest: service.image_digest,
        replicas: service.replicas,
        ports: service.ports,
        health_check: service.health_check,
        cpu_reservation: service.cpu_reservation,
        cpu_limit: service.cpu_limit,
        memory_reservation: service.memory_reservation,
        memory_limit: service.memory_limit,
        constraints: service.constraints,
        revision: service.desired_revision
      },

      # Actual state (what Swarm is running)
      actual: {
        replicas_desired: latest_observation&.desired_tasks || 0,
        replicas_running: latest_observation&.running_tasks || 0,
        replicas_healthy: latest_observation&.healthy_tasks || 0,
        replicas_failed: latest_observation&.failed_tasks || 0,
        image_digest: latest_observation&.observed_image_digest,
        nodes: latest_observation&.nodes || [],
        update_status: latest_observation&.update_status,
        revision: service.applied_revision,
        observed_at: latest_observation&.observed_at&.iso8601
      },

      # Derived status and observation metadata
      status: presented_status,
      observation_stale: observation_stale,
      observation_age_seconds: observation_age_seconds,

      # Legacy fields for backward compatibility
      technical_name: service.technical_name,
      created_at: service.created_at&.iso8601,
      updated_at: service.updated_at&.iso8601
    }

    Opanel::Result.success(data)
  end

  private

  attr_reader :actor, :service
end
