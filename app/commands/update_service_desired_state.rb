# Updates the desired state of a Service (doc 09 §5.3, §17).
#
# ## Optimistic concurrency
#
# The `expected_revision` parameter allows the caller to check for lost updates.
# If the Service's current desired_revision does not match, the command returns
# REVISION_CONFLICT rather than silently overwriting (AC4).
#
# ## Meaningful revisions
#
# desired_revision increments only when a field that the reconciler observes
# actually changes (replicas, image, resources, etc.). Cosmetic changes (name,
# constraints) do not increment the revision because the reconciler does not
# care about them.
#
class UpdateServiceDesiredState
  REVISION_CONFLICT = "The service has been modified. Refresh and try again."
  SERVICE_NOT_FOUND = "Service not found."
  INVALID_IMAGE_REF = "The image reference is invalid."
  INVALID_REPLICAS = "Replicas must be a positive number."
  INVALID_STATE_TRANSITION = "That state change is not allowed."
  RESOURCES_INVALID = "Resource limits must be greater than or equal to reservations."

  def self.call(actor:, service:, service_id: nil, expected_revision: nil, replicas: nil,
    image_ref: nil, ports: nil, health_check: nil, cpu_reservation: nil, cpu_limit: nil,
    memory_reservation: nil, memory_limit: nil, constraints: nil)
    service = TenantScope.for(actor, Service).find_by_external_id(:service, service_id) if service_id && !service
    new(actor: actor, service: service, expected_revision: expected_revision, replicas: replicas,
      image_ref: image_ref, ports: ports, health_check: health_check,
      cpu_reservation: cpu_reservation, cpu_limit: cpu_limit,
      memory_reservation: memory_reservation, memory_limit: memory_limit,
      constraints: constraints).call
  end

  def initialize(actor:, service:, expected_revision:, replicas:, image_ref:, ports:,
    health_check:, cpu_reservation:, cpu_limit:, memory_reservation:, memory_limit:, constraints:)
    @actor = actor
    @service = service
    @expected_revision = expected_revision
    @replicas = replicas
    @image_ref = image_ref.to_s.strip if image_ref.present?
    @ports = ports
    @health_check = health_check
    @cpu_reservation = cpu_reservation
    @cpu_limit = cpu_limit
    @memory_reservation = memory_reservation
    @memory_limit = memory_limit
    @constraints = constraints
  end

  def call
    return failure("NOT_FOUND", SERVICE_NOT_FOUND) if service.nil?

    # Authorization (AF-07).
    policy = ServicePolicy.new(actor, service)
    return failure("FORBIDDEN", ApplicationPolicy::REASONS[:insufficient_role], field: "status") unless policy.update?

    # AC4: Optimistic concurrency check. If the caller has an expected_revision
    # and it does not match, return REVISION_CONFLICT without mutating.
    if expected_revision.present?
      begin
        coerced_revision = Integer(expected_revision)
      rescue ArgumentError
        return failure("VALIDATION_ERROR", "expected_revision must be an integer", field: "expected_revision")
      end

      if coerced_revision != service.desired_revision
        return failure("REVISION_CONFLICT", REVISION_CONFLICT,
          current_revision: service.desired_revision, expected_revision: coerced_revision)
      end
    end

    # Collect changes that affect desired_revision (reconciler observes these).
    reconciler_affected = false

    # Validate individual fields as they are provided.
    if replicas.present?
      begin
        replicas_count = Integer(replicas)
        return failure("VALIDATION_ERROR", INVALID_REPLICAS, field: "replicas") if replicas_count <= 0
      rescue ArgumentError
        return failure("VALIDATION_ERROR", INVALID_REPLICAS, field: "replicas")
      end
      reconciler_affected = true if replicas_count != service.replicas
    end

    if image_ref.present?
      begin
        image_parser = Opanel::ImageRef.new(image_ref)
        parsed_image = image_parser.parse
      rescue Opanel::ImageRef::InvalidReference => e
        return failure("VALIDATION_ERROR", INVALID_IMAGE_REF, field: "image_ref", details: e.message)
      end
      reconciler_affected = true if image_ref != service.image_ref
    end

    if (cpu_reservation.present? || cpu_limit.present?) || (memory_reservation.present? || memory_limit.present?)
      new_cpu_res = cpu_reservation.presence || service.cpu_reservation
      new_cpu_lim = cpu_limit.presence || service.cpu_limit
      new_mem_res = memory_reservation.presence || service.memory_reservation
      new_mem_lim = memory_limit.presence || service.memory_limit

      if new_cpu_lim && new_cpu_res && new_cpu_lim < new_cpu_res
        return failure("VALIDATION_ERROR", RESOURCES_INVALID, field: "cpu")
      end
      if new_mem_lim && new_mem_res && new_mem_lim < new_mem_res
        return failure("VALIDATION_ERROR", RESOURCES_INVALID, field: "memory")
      end

      # Check if resources actually changed.
      if cpu_reservation.present? && cpu_reservation != service.cpu_reservation
        reconciler_affected = true
      end
      if cpu_limit.present? && cpu_limit != service.cpu_limit
        reconciler_affected = true
      end
      if memory_reservation.present? && memory_reservation != service.memory_reservation
        reconciler_affected = true
      end
      if memory_limit.present? && memory_limit != service.memory_limit
        reconciler_affected = true
      end
    end

    if ports.present?
      reconciler_affected = true if ports != service.ports
    end

    if health_check.present?
      reconciler_affected = true if health_check != service.health_check
    end

    persist(replicas_count, reconciler_affected)
  end

  private

  attr_reader :actor, :service, :expected_revision, :replicas, :image_ref, :ports, :health_check, :cpu_reservation,
:cpu_limit, :memory_reservation, :memory_limit, :constraints

  def persist(replicas_count, reconciler_affected)
    before = service.attributes.dup

    ApplicationRecord.transaction do
      # Update fields.
      service.replicas = replicas_count if replicas.present?
      service.image_ref = image_ref if image_ref.present?
      service.ports = ports if ports.present?
      service.health_check = health_check if health_check.present?
      service.cpu_reservation = cpu_reservation if cpu_reservation.present?
      service.cpu_limit = cpu_limit if cpu_limit.present?
      service.memory_reservation = memory_reservation if memory_reservation.present?
      service.memory_limit = memory_limit if memory_limit.present?
      service.constraints = constraints if constraints.present?

      # Only increment desired_revision if the reconciler observes a change.
      service.desired_revision += 1 if reconciler_affected

      service.save!

      AuditTrail.record(action: :service_updated, actor: actor, resource: service,
        before: before, after: service.attributes)
    end

    Rails.logger.info(event: "service.updated", team_id: service.team.external_id,
      project_id: service.environment.project.external_id,
      environment_id: service.environment.external_id, service_id: service.external_id,
      actor_id: actor.external_id, result: "succeeded",
      desired_revision: service.desired_revision)

    Opanel::Result.success(service: service)
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "service.updated", team_id: service&.team&.external_id,
      project_id: service&.environment&.project&.external_id,
      environment_id: service&.environment&.external_id, service_id: service&.external_id,
      actor_id: actor&.external_id, result: "rejected", reason: code)

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
