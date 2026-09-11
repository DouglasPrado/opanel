# Ownership labels and deterministic naming for Swarm resources.
#
# ## The ownership namespace
#
# Every resource created by the platform is marked with labels in the `com.opanel.*`
# namespace (ADR-0001). The namespace is defined here once; nothing else in the codebase
# composes a label key (AC1).
#
# ## Three responsibilities
#
# 1. **labels_for(resource)** — returns the complete set of ownership labels for a
#    model instance (Service, Network, Secret, Config, etc.). Labels carry opaque IDs
#    and the desired revision, never human names or secrets (AC6).
#
# 2. **technical_name_for(resource)** — derives a stable technical name from opaque
#    IDs, not slugs. Renaming a parent does not change the technical name (AC3).
#
# 3. **managed_by_platform?(runtime_resource)** — the safety predicate. A resource is
#    only "ours" if it carries com.opanel.managed=true AND the IDs are internally
#    consistent. Ambiguous cases default to "not ours" (AC5).
#
module Opanel::Ownership
  # The namespace constant that appears exactly here, nowhere else (AC1).
  NAMESPACE = "com.opanel"

  # The keys in the ownership label set (doc 07 §7, reproduced exactly in ADR-0001).
  LABEL_KEYS = %w[managed team_id project_id environment_id service_id release_id desired_revision].freeze

  class << self
    # Returns the complete set of ownership labels for a resource.
    #
    # - Service: all keys except release_id (set when it exists)
    # - Environment / Network / Secret / Config: service_id and release_id omitted
    # - Resource without team_id: returns empty (should not happen in the platform)
    #
    # Labels contain only opaque IDs and the desired revision, never secrets or names.
    # AC6: a label with a human name is a security violation.
    def labels_for(resource)
      labels = {}
      labels["#{NAMESPACE}.managed"] = "true"

      # team_id: mostly all managed resources have this directly
      if resource.respond_to?(:team_id)
        labels["#{NAMESPACE}.team_id"] = external_id(resource.team_id, :team)
      end

      # project_id: most resources have this; Services have it through environment
      if resource.respond_to?(:project_id)
        labels["#{NAMESPACE}.project_id"] = external_id(resource.project_id, :project)
      elsif resource.is_a?(Service)
        labels["#{NAMESPACE}.project_id"] = external_id(resource.environment.project_id, :project)
      end

      # environment_id: Environment is itself; others have it as a foreign key
      if resource.is_a?(Environment)
        labels["#{NAMESPACE}.environment_id"] = external_id(resource.id, :environment)
      elsif resource.respond_to?(:environment_id)
        labels["#{NAMESPACE}.environment_id"] = external_id(resource.environment_id, :environment)
      end

      # service_id: only for Services
      if resource.is_a?(Service)
        labels["#{NAMESPACE}.service_id"] = external_id(resource.id, :service)
      end

      # release_id: only for Releases (when that entity is introduced)
      if defined?(Release) && resource.is_a?(Release)
        labels["#{NAMESPACE}.release_id"] = external_id(resource.id, :release)
      end

      # desired_revision: present on versioned resources (never nil in practice, but defensive)
      if resource.respond_to?(:desired_revision) && resource.desired_revision.present?
        labels["#{NAMESPACE}.desired_revision"] = resource.desired_revision.to_s
      end

      labels.compact
    end

    # Returns a deterministic technical name derived from opaque IDs, not slugs.
    #
    # Pattern (after ADR-0009 §5 and accounting for the Engine's 63-character limit):
    # - Service: svc_<serviceId> (34 characters maximum)
    # - Network: net_<environmentId> (34 characters maximum)
    # - Certificate: cert_<certificateId> (when the entity exists)
    # - Secret: vault_<secretVersionId>
    #
    # The name is stable; renaming a Team, Project, Environment or Service does not
    # change it (AC3). The product never uses this name as a primary identifier; it is
    # metadata for the Swarm resource itself (doc 09 §195: "derivado de IDs/slugs
    # sanitizados, mas o produto **nunca depende desse nome como identificador primário**").
    #
    # The original scheme (net_<projectId>_<environmentId>, 65 characters) exceeded the
    # Engine's 63-character limit for every Environment. ADR-0009 §5 addresses owned
    # resources by ownership label (com.opanel.environment_id, com.opanel.service_id, etc),
    # so the technical name is no longer looked up. The names derived here carry only
    # sufficient information to be stable and collision-free by construction — each
    # Environment ULID is unique within the cluster, and each Service ULID is unique
    # within its Environment. Truncating a ULID would make collision probabilistic,
    # violating M01-16 AC8; a hash digest would stop being "derivado de IDs".
    def technical_name_for(resource)
      case resource
      when Service
        service_id = external_id(resource.id, :service)
        "svc_#{service_id}"
      when Environment
        environment_id = external_id(resource.id, :environment)
        "net_#{environment_id}"
      else
        raise ArgumentError, "technical_name_for does not support #{resource.class}"
      end
    end

    # The ownership predicate: is this runtime resource managed by the platform?
    #
    # Takes a RuntimeObservation (ADR-0009 §4) and returns true only if:
    # 1. com.opanel.managed=true is present in labels
    # 2. All IDs in the labels resolve correctly
    # 3. The resolved IDs match the entities they point to
    #
    # A resource claiming managed=true with inconsistent IDs is logged as an anomaly
    # (AC5) and returns false — we do not adopt it, and we do not delete it. The default
    # failure mode is "not ours" (AC5).
    def managed_by_platform?(observation)
      return false unless observation.is_a?(Opanel::RuntimeObservation)

      labels = observation.labels
      return false unless labels["#{NAMESPACE}.managed"] == "true"

      # Decode the IDs. If any step fails, log and return false.
      team_id = labels["#{NAMESPACE}.team_id"]
      project_id = labels["#{NAMESPACE}.project_id"]
      environment_id = labels["#{NAMESPACE}.environment_id"]
      service_id = labels["#{NAMESPACE}.service_id"]
      desired_revision = labels["#{NAMESPACE}.desired_revision"]

      # All required IDs must be present. Services have service_id; networks don't.
      required_ids = [ team_id, project_id, environment_id ]
      if required_ids.any?(&:blank?)
        log_anomaly(observation, "missing required ID labels")
        return false
      end

      # IDs must be decodable and resolvable to actual records (AC5).
      # This is a cross-tenant ownership check — validating a runtime resource against our
      # installation's IDs, regardless of team. AC5 requires this deliberately unscoped lookup.
      # Nil = row does not exist → safe "not ours" default.
      # rubocop:disable Opanel/UnscopedTenantQuery -- M01-16: the ownership predicate is deliberately installation-wide; there is no actor to scope by, and a missing row must answer "not ours"
      begin
        team = Team.find_by(id: Opanel::Identifier.parse(:team, team_id)) if team_id
        project = Project.find_by(id: Opanel::Identifier.parse(:project, project_id)) if project_id
        environment = Environment.find_by(id: Opanel::Identifier.parse(:environment, environment_id)) if environment_id
        service = Service.find_by(id: Opanel::Identifier.parse(:service, service_id)) if service_id
      rescue Opanel::Identifier::InvalidIdentifier => e
        log_anomaly(observation, "ID decode failed: #{e.message}")
        return false
      end
      # rubocop:enable Opanel/UnscopedTenantQuery

      # IDs must be consistent (AC5).
      if team && project && project.team_id != team.id
        log_anomaly(observation, "project.team_id does not match label team_id")
        return false
      end

      if project && environment && environment.project_id != project.id
        log_anomaly(observation, "environment.project_id does not match label project_id")
        return false
      end

      if environment && service && service.environment_id != environment.id
        log_anomaly(observation, "service.environment_id does not match label environment_id")
        return false
      end

      true
    end

    private

    # Convert an internal ULID to its external representation (prefixed).
    # The type must be specified because it determines the prefix.
    def external_id(id, type)
      return nil if id.blank?
      Opanel::Identifier.external(type, id)
    end

    # Log an anomaly for manual review. AC5: resources with managed=true and
    # inconsistent IDs are never removed automatically; this is the audit trail.
    def log_anomaly(observation, reason)
      Rails.logger.warn(
        event: "ownership.anomaly",
        reason: reason,
        resource_type: observation.kind,
        resource_id: observation.runtime_id,
        resource_name: observation.name
      )
    end

    # Determine the type of runtime resource from a RuntimeObservation.
    def resource_type_for(observation)
      observation.kind
    end
  end
end
