# A view of a Service's runtime state (doc 10 UC-013).
#
# This query returns desired state (from the Service table) and, once M01-19
# lands, actual state (from ServiceObservation). For M01-12, only desired state
# is included.
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

    # For M01-12, return only desired state. Actual state joins in M01-19.
    data = {
      id: service.external_id,
      environment_id: service.environment.external_id,
      name: service.name,
      slug: service.slug,
      service_type: service.service_type,
      image_ref: service.image_ref,
      replicas: service.replicas,
      ports: service.ports,
      health_check: service.health_check,
      cpu_reservation: service.cpu_reservation,
      cpu_limit: service.cpu_limit,
      memory_reservation: service.memory_reservation,
      memory_limit: service.memory_limit,
      constraints: service.constraints,
      status: service.status,
      desired_revision: service.desired_revision,
      applied_revision: service.applied_revision,
      technical_name: service.technical_name,
      created_at: service.created_at&.iso8601,
      updated_at: service.updated_at&.iso8601
    }

    Opanel::Result.success(data)
  end

  private

  attr_reader :actor, :service
end
