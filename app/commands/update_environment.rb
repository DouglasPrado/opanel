# Updates an Environment's configuration (doc 09 §5.2).
#
# ## Meaningful revisions
#
# A revision increment signals that the reconciler must observe this Environment
# and converge it. Only fields that the reconciler cares about trigger an increment;
# cosmetic changes like `name` do not.
#
# ## What can be changed
#
# In M01, only `name` and `slug` may be changed — the UX fields. The Cluster,
# type, and secrets config are locked until later Milestones provide the
# operations to handle their changes (move between Clusters, change type, etc.).
class UpdateEnvironment
  NAME_REQUIRED = "Enter a name for the environment."
  NAME_TOO_LONG = "That name is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "An environment name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That environment name is already used by this project."

  def self.call(actor:, environment:, name: nil, slug: nil)
    new(actor: actor, environment: environment, name: name, slug: slug).call
  end

  def initialize(actor:, environment:, name:, slug:)
    @actor = actor
    @environment = environment
    @name = name.to_s.strip.presence
    @requested_slug = slug.to_s.strip.downcase.presence
  end

  def call
    # Authorization (AF-07): reach the Policy directly.
    policy = EnvironmentPolicy.new(actor, environment)
    return failure("CONFLICT", ApplicationPolicy::REASONS[:insufficient_role], field: "status") unless policy.update?

    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if @name == ""
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if @name && @name.length > Environment::NAME_MAX_LENGTH

    if @requested_slug
      resolved_slug = @requested_slug
      return failure("VALIDATION_ERROR", SLUG_INVALID, field: "slug") if resolved_slug.nil? || !resolved_slug.match?(Environment::SLUG_FORMAT)
      return slug_taken(resolved_slug) if taken?(resolved_slug)
    end

    persist
  rescue ActiveRecord::RecordNotUnique
    slug_taken(@requested_slug)
  end

  private

  attr_reader :actor, :environment

  def persist
    before = {}
    updates = {}

    if @name
      before["name"] = environment.name
      updates[:name] = @name
    end

    if @requested_slug
      before["slug"] = environment.slug
      updates[:slug] = @requested_slug
    end

    # Only slug changes trigger a revision increment; name is cosmetic.
    if @requested_slug
      before["desired_revision"] = environment.desired_revision
      updates[:desired_revision] = environment.desired_revision + 1
    end

    ApplicationRecord.transaction do
      environment.update!(updates)

      AuditTrail.record(action: :environment_updated, actor: actor, resource: environment,
        before: before, after: environment.attributes.slice(*before.keys))
    end

    Rails.logger.info(event: "environment.updated", team_id: environment.team.external_id,
      project_id: environment.project.external_id, environment_id: environment.external_id,
      actor_id: actor.external_id, result: "succeeded")

    Opanel::Result.success(environment: environment)
  end

  def taken?(slug)
    environment.project.environments.kept.where.not(id: environment.id).exists?(slug: slug)
  end

  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug",
      suggestion: Environment.suggest_slug(project: environment.project, taken: slug, excluding: environment.id))
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "environment.updated", team_id: environment&.team&.external_id,
      project_id: environment&.project&.external_id, environment_id: environment&.external_id,
      actor_id: actor&.external_id, result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
