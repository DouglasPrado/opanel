# Creates a Service linking an Environment to an OCI image (doc 09 §5.3).
#
# ## Image reference validation and mutable tag resolution
#
# The image_ref is validated and normalized. If it contains a mutable tag (not a
# digest), the command resolves it to the immutable digest from the registry
# (AC7). For M01-12, resolution is a placeholder; M06 will make it real.
#
# ## Tenant scoping
#
# The Environment lookup is scoped to the actor's Teams. An attempt to create a
# Service in another Team's Environment is indistinguishable from a nonexistent
# Environment (AC4).
#
# ## Technical naming
#
# The `technical_name` is derived from team/project/environment/service IDs to
# be deterministic, but the product never uses it as a primary identifier (doc 09 §5.3).
#
class CreateService
  NAME_REQUIRED = "Enter a name for the service."
  NAME_TOO_LONG = "That name is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "A service name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That service name is already used by this environment."
  ENVIRONMENT_NOT_FOUND = "Environment not found."
  ENVIRONMENT_NOT_READY = "The environment is not active. Create services in an active environment."
  INVALID_IMAGE_REF = "The image reference is invalid."
  INVALID_REPLICAS = "Replicas must be a positive number."
  INVALID_SERVICE_TYPE = "That service type is not recognized."
  RESOURCES_INVALID = "Resource limits must be greater than or equal to reservations."
  UNLIMITABLE_RESOURCE = "Services without resource limits may cause platform instability."

  def self.call(actor:, environment:, environment_id: nil, name:, slug: nil, image_ref:,
    service_type: "WEB", replicas: 1, ports: {}, health_check: nil, cpu_reservation: nil,
    cpu_limit: nil, memory_reservation: nil, memory_limit: nil, constraints: nil)
    environment = TenantScope.for(actor, Environment).find_by_external_id(:environment,
environment_id) if environment_id && !environment
    new(actor: actor, environment: environment, name: name, slug: slug, image_ref: image_ref,
      service_type: service_type, replicas: replicas, ports: ports, health_check: health_check,
      cpu_reservation: cpu_reservation, cpu_limit: cpu_limit,
      memory_reservation: memory_reservation, memory_limit: memory_limit,
      constraints: constraints).call
  end

  def initialize(actor:, environment:, name:, slug:, image_ref:, service_type:, replicas:, ports:,
    health_check:, cpu_reservation:, cpu_limit:, memory_reservation:, memory_limit:, constraints:)
    @actor = actor
    @environment = environment
    @name = name.to_s.strip
    @requested_slug = slug.to_s.strip.downcase.presence
    @image_ref = image_ref.to_s.strip
    @service_type = service_type
    @replicas = replicas
    @ports = ports || {}
    @health_check = health_check
    @cpu_reservation = cpu_reservation
    @cpu_limit = cpu_limit
    @memory_reservation = memory_reservation
    @memory_limit = memory_limit
    @constraints = constraints
  end

  def call
    # Authorization (AF-07): reach the Policy. Build an unsaved Service for
    # authorization; the Policy reads the Team from it.
    temp_service = Service.new(environment: environment, team: environment&.team)
    policy = ServicePolicy.new(actor, temp_service)
    return failure("FORBIDDEN", ApplicationPolicy::REASONS[:insufficient_role], field: "status") unless policy.create?

    # AC1: Environment must exist and belong to the actor's team.
    return failure("NOT_FOUND", ENVIRONMENT_NOT_FOUND) if environment.nil?

    # AC6: Environment must be active (READY status, not soft-deleted).
    return failure("VALIDATION_ERROR", ENVIRONMENT_NOT_READY,
      field: "environment") unless environment.deleted_at.nil? && environment.ready?

    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if name.blank?
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if name.length > Service::NAME_MAX_LENGTH

    # Validate and normalize image reference (AC7).
    begin
      image_parser = Opanel::ImageRef.new(image_ref)
      parsed_image = image_parser.parse
    rescue Opanel::ImageRef::InvalidReference => e
      return failure("VALIDATION_ERROR", INVALID_IMAGE_REF, field: "image_ref", details: e.message)
    end

    # Validate service type.
    return failure("VALIDATION_ERROR", INVALID_SERVICE_TYPE, field: "service_type") unless Service::TYPES.include?(service_type)

    # Validate replicas.
    begin
      replicas_count = Integer(replicas)
      return failure("VALIDATION_ERROR", INVALID_REPLICAS, field: "replicas") if replicas_count <= 0
    rescue ArgumentError
      return failure("VALIDATION_ERROR", INVALID_REPLICAS, field: "replicas")
    end

    # Validate resource constraints.
    if (cpu_reservation || cpu_limit) && cpu_limit && cpu_reservation && cpu_limit < cpu_reservation
      return failure("VALIDATION_ERROR", RESOURCES_INVALID, field: "cpu")
    end
    if (memory_reservation || memory_limit) && memory_limit && memory_reservation && memory_limit < memory_reservation
      return failure("VALIDATION_ERROR", RESOURCES_INVALID, field: "memory")
    end

    # AC9: Warn if resources are unbounded.
    if (cpu_reservation.nil? && cpu_limit.nil?) || (memory_reservation.nil? && memory_limit.nil?)
      Rails.logger.warn(event: "service.created", message: UNLIMITABLE_RESOURCE,
        team_id: environment.team.external_id, environment_id: environment.external_id,
        actor_id: actor.external_id)
    end

    slug = resolved_slug
    return failure("VALIDATION_ERROR", slug_error, field: "slug") if slug.nil?
    return slug_taken(slug) if taken?(slug)

    persist(parsed_image, replicas_count, slug)
  rescue ActiveRecord::RecordNotUnique
    slug_taken(resolved_slug)
  end

  private

  attr_reader :actor, :environment, :name, :requested_slug, :image_ref, :service_type, :replicas, :ports,
:health_check, :cpu_reservation, :cpu_limit, :memory_reservation, :memory_limit, :constraints

  def persist(parsed_image, replicas_count, slug)
    svc = nil

    ApplicationRecord.transaction do
      technical_name = derive_technical_name(slug)

      svc = Service.create!(
        environment: environment,
        team: environment.team,  # Denormalized for tenant scoping
        name: name,
        slug: slug,
        service_type: service_type,
        image_ref: image_ref,
        replicas: replicas_count,
        ports: ports,
        health_check: health_check,
        cpu_reservation: cpu_reservation,
        cpu_limit: cpu_limit,
        memory_reservation: memory_reservation,
        memory_limit: memory_limit,
        constraints: constraints,
        technical_name: technical_name,
        status: Service::DRAFT,
        desired_revision: 1
      )

      AuditTrail.record(action: :service_created, actor: actor, resource: svc,
        after: svc.attributes)
    end

    Rails.logger.info(event: "service.created", team_id: environment.team.external_id,
      project_id: environment.project.external_id, environment_id: environment.external_id,
      service_id: svc.external_id, actor_id: actor.external_id, result: "succeeded",
      desired_revision: svc.desired_revision)

    Opanel::Result.success(service: svc)
  end

  def derive_technical_name(slug)
    # Deterministic name derived from team/project/environment/service IDs.
    # Format: {team-slug}-{project-slug}-{env-slug}-{svc-slug}
    "#{environment.project.team.slug}-#{environment.project.slug}-#{environment.slug}-#{slug}"
  end

  def resolved_slug
    @resolved_slug ||= requested_slug || Service.slugify(name)
  end

  def slug_error
    requested_slug ? SLUG_INVALID : SLUG_UNUSABLE
  end

  def taken?(slug)
    return true unless slug.match?(Service::SLUG_FORMAT)

    environment.services.kept.exists?(slug: slug)
  end

  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug",
      suggestion: Service.suggest_slug(environment: environment, taken: slug))
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "service.created", team_id: environment&.team&.external_id,
      project_id: environment&.project&.external_id, environment_id: environment&.external_id,
      actor_id: actor&.external_id, result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
