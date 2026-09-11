# Creates a Project inside a Team (doc 09 §5.1, UC-009, AC1).
#
# ## The authorization subject is the Team
#
# There is no Project yet, so the decision cannot be scoped to one. It is scoped
# to the Team the Project will belong to, through the row doc 04 §6.2 already
# assigns (`create_project`). The Team itself arrives already resolved through the
# tenancy boundary — this Command never looks one up by id, which is what
# Annex C §7.3 forbids.
#
# ## Slug collisions are an outcome, not an exception
#
# doc 10 §7.2 asks for a short flow, and the Story's failure table asks for
# *"validação inline com sugestão; sem perder o formulário preenchido"*. A taken
# slug therefore comes back as a `VALIDATION_ERROR` naming the field and offering
# a free alternative, exactly as `CreateTeam` does — the same problem, so the same
# shape, rather than a second convention for the reader to learn.
class CreateProject
  NAME_REQUIRED = "Enter a name for the project."
  NAME_TOO_LONG = "That name is too long."
  DESCRIPTION_TOO_LONG = "That description is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "A URL name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That URL name is already used by another project in this team."

  def self.call(actor:, team:, name:, slug: nil, description: nil)
    new(actor: actor, team: team, name: name, slug: slug, description: description).call
  end

  def initialize(actor:, team:, name:, slug: nil, description: nil)
    @actor = actor
    @team = team
    @name = name.to_s.strip
    @requested_slug = slug.to_s.strip.downcase.presence
    @description = description.to_s.strip.presence
  end

  def call
    Opanel::Authorization.authorize!(actor, :create_project, team)

    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if name.blank?
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if name.length > Project::NAME_MAX_LENGTH

    if description && description.length > Project::DESCRIPTION_MAX_LENGTH
      return failure("VALIDATION_ERROR", DESCRIPTION_TOO_LONG, field: "description")
    end

    slug = resolved_slug
    return failure("VALIDATION_ERROR", slug_error, field: "slug") if slug.nil?
    return slug_taken(slug) if taken?(slug)

    persist(slug)
  rescue ActiveRecord::RecordNotUnique
    # The check-then-insert window is real; the partial unique index is what
    # closes it. Losing the race has to be indistinguishable from finding the
    # slug taken, or the two paths drift and only one stays correct.
    slug_taken(resolved_slug)
  end

  private

  attr_reader :actor, :team, :name, :requested_slug, :description

  def persist(slug)
    project = nil

    ApplicationRecord.transaction do
      project = Project.create!(team: team, name: name, slug: slug, description: description,
        status: Project::ACTIVE)

      # Inside the transaction: M01-05 AC11 makes audit and mutation share one,
      # so a trail that cannot be written takes the mutation with it rather than
      # leaving a Project whose creation nobody can see.
      AuditTrail.record(action: :project_created, actor: actor, resource: project,
        after: project.attributes)
    end

    Rails.logger.info(event: "project.created", team_id: team.external_id,
      project_id: project.external_id, actor_id: actor.external_id, result: "succeeded")

    Opanel::Result.success(project: project)
  end

  def resolved_slug
    @resolved_slug ||= requested_slug || Project.slugify(name)
  end

  def slug_error
    requested_slug ? SLUG_INVALID : SLUG_UNUSABLE
  end

  # Scoped to the Team, which is what makes AC3 true: the same slug in another
  # Team is not a collision and must not be reported as one.
  def taken?(slug)
    return true unless slug.match?(Project::SLUG_FORMAT)

    team.projects.kept.exists?(slug: slug)
  end

  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug",
      suggestion: Project.suggest_slug(team: team, taken: slug))
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "project.created", team_id: team&.external_id,
      actor_id: actor&.external_id, result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
