# Creates an Environment linking a Project to a Cluster (doc 09 §5.2).
#
# ## Tenant scoping and the AC4 leak path
#
# The Cluster lookup is scoped to the Project's Team (M01-04 AC5). An Environment
# pointing at another Team's Cluster is never created, and the error response is
# indistinguishable from a nonexistent Cluster — no detail reveals whether it exists
# or whether authorization denied it (AC4, Annex C §7.3).
#
# ## Meaningful revisions
#
# Every field that a reconciler observes increments `desired_revision` when changed.
# Initial creation starts at revision 1, and that is incremented here rather than
# left to the database default, because a meaningful create must be observable.
class CreateEnvironment
  NAME_REQUIRED = "Enter a name for the environment."
  NAME_TOO_LONG = "That name is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "An environment name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That environment name is already used by this project."
  CLUSTER_NOT_FOUND = "Cluster not found."
  CLUSTER_NOT_READY = "The cluster is not ready. Choose a cluster with status READY."

  def self.call(actor:, project:, cluster: nil, cluster_id: nil, name:, slug: nil, type: "DEVELOPMENT",
auto_promote_secrets: nil)
    cluster = TenantScope.for(actor, Cluster).find_by_external_id(:cluster, cluster_id) if cluster_id && !cluster
    new(actor: actor, project: project, cluster: cluster, name: name, slug: slug,
      type: type, auto_promote_secrets: auto_promote_secrets).call
  end

  def initialize(actor:, project:, cluster:, name:, slug:, type:, auto_promote_secrets:)
    @actor = actor
    @project = project
    @cluster = cluster
    @name = name.to_s.strip
    @requested_slug = slug.to_s.strip.downcase.presence
    @type = type
    @auto_promote_secrets = auto_promote_secrets
  end

  def call
    # Authorization (AF-07): reach the Policy. Build an unsaved Environment for
    # authorization; the Policy reads the Team from it (doc 04 §6.2).
    temp_env = Environment.new(project: project, team: project.team)
    policy = EnvironmentPolicy.new(actor, temp_env)
    return failure("CONFLICT", ApplicationPolicy::REASONS[:insufficient_role], field: "status") unless policy.create?

    # AC4: Cluster must belong to the same Team, never revealed if it doesn't.
    return failure("NOT_FOUND", CLUSTER_NOT_FOUND) if cluster.nil?

    # AC9: Cluster must be READY for an Environment to be created on it.
    # DEGRADED, PROVISIONING, UNREACHABLE and other states mean the cluster
    # cannot reliably execute workloads.
    return failure("VALIDATION_ERROR", CLUSTER_NOT_READY, field: "cluster") unless cluster.ready?

    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if name.blank?
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if name.length > Environment::NAME_MAX_LENGTH

    slug = resolved_slug
    return failure("VALIDATION_ERROR", slug_error, field: "slug") if slug.nil?
    return slug_taken(slug) if taken?(slug)

    persist(slug)
  rescue ActiveRecord::RecordNotUnique
    slug_taken(resolved_slug)
  end

  private

  attr_reader :actor, :project, :cluster, :name, :requested_slug, :type, :auto_promote_secrets

  def persist(slug)
    env = nil

    ApplicationRecord.transaction do
      # AC5: PRODUCTION defaults to false. Non-PRODUCTION defaults to false.
      # The database CHECK forbids true in PRODUCTION, so no bypass is possible.
      promote_secrets = @auto_promote_secrets.nil? ? false : @auto_promote_secrets

      env = Environment.create!(
        project: project,
        cluster: cluster,
        team: project.team,  # Denormalized for tenant scoping
        name: name,
        slug: slug,
        type: type,
        auto_promote_secrets: promote_secrets,
        status: Environment::PROVISIONING,
        desired_revision: 1
      )

      AuditTrail.record(action: :environment_created, actor: actor, resource: env,
        after: env.attributes)
    end

    Rails.logger.info(event: "environment.created", team_id: project.team.external_id,
      project_id: project.external_id, environment_id: env.external_id,
      cluster_id: cluster.external_id, actor_id: actor.external_id, result: "succeeded")

    Opanel::Result.success(environment: env)
  end

  def resolved_slug
    @resolved_slug ||= requested_slug || Environment.slugify(name)
  end

  def slug_error
    requested_slug ? SLUG_INVALID : SLUG_UNUSABLE
  end

  def taken?(slug)
    return true unless slug.match?(Environment::SLUG_FORMAT)

    project.environments.kept.exists?(slug: slug)
  end

  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug",
      suggestion: Environment.suggest_slug(project: project, taken: slug))
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "environment.created", team_id: project&.team&.external_id,
      project_id: project&.external_id, actor_id: actor&.external_id,
      result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
