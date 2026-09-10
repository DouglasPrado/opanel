# Renames a Project, or edits its description (AC7, AC8).
#
# The slug is editable and **nothing references it** — every pointer at a Project
# is its ULID (doc 09 §19, ADR-0002). That is what makes a rename an ordinary
# update instead of a migration: no row has to be rewritten, no Swarm label
# changes, and a URL that used the old slug simply stops resolving, which is the
# correct behaviour for a name somebody chose to change.
#
# The Project arrives already resolved through the tenancy boundary. This Command
# never looks one up by id.
class UpdateProject
  NAME_REQUIRED = "Enter a name for the project."
  NAME_TOO_LONG = "That name is too long."
  DESCRIPTION_TOO_LONG = "That description is too long."
  SLUG_INVALID = "A URL name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That URL name is already used by another project in this team."
  # Says what is true and promises nothing: restoring an archived Project is not
  # a capability this Milestone ships, so the message must not point at one.
  NOT_ACTIVE = "This project is archived and can no longer be edited."

  # A sentinel, because `nil` is a legitimate new value for `description` — it is
  # how the field is cleared — and an omitted argument is not the same request as
  # one that clears it. Without this, "leave the description alone" and "remove
  # the description" are the same call.
  UNCHANGED = Object.new.freeze

  def self.call(actor:, project:, name: UNCHANGED, slug: UNCHANGED, description: UNCHANGED)
    new(actor: actor, project: project, name: name, slug: slug, description: description).call
  end

  def initialize(actor:, project:, name:, slug:, description:)
    @actor = actor
    @project = project
    @name = name
    @slug = slug
    @description = description
  end

  def call
    Opanel::Authorization.authorize!(actor, :update, project)

    return failure("CONFLICT", NOT_ACTIVE, field: "status") unless project.active?

    changes = {}
    changes[:name] = normalized_name if changed?(@name)
    changes[:slug] = normalized_slug if changed?(@slug)
    changes[:description] = normalized_description if changed?(@description)

    error = validate(changes)
    return error if error

    return Opanel::Result.success(project: project) if changes.empty?

    persist(changes)
  rescue ActiveRecord::RecordNotUnique
    slug_taken(changes_slug)
  end

  private

  attr_reader :actor, :project

  def changed?(value) = !value.equal?(UNCHANGED)

  def normalized_name = @name.to_s.strip
  def normalized_slug = @slug.to_s.strip.downcase
  def normalized_description = @description.nil? ? nil : @description.to_s.strip.presence

  def changes_slug = changed?(@slug) ? normalized_slug : project.slug

  def validate(changes)
    if changes.key?(:name)
      return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if changes[:name].blank?

      if changes[:name].length > Project::NAME_MAX_LENGTH
        return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name")
      end
    end

    if changes.key?(:description) && changes[:description].to_s.length > Project::DESCRIPTION_MAX_LENGTH
      return failure("VALIDATION_ERROR", DESCRIPTION_TOO_LONG, field: "description")
    end

    validate_slug(changes)
  end

  def validate_slug(changes)
    return nil unless changes.key?(:slug)

    slug = changes[:slug]
    unless slug.match?(Project::SLUG_FORMAT) &&
        slug.length.between?(Project::SLUG_MIN_LENGTH, Project::SLUG_MAX_LENGTH)
      return failure("VALIDATION_ERROR", SLUG_INVALID, field: "slug")
    end

    # Scoped to the Team and excluding this Project: renaming a Project to the
    # slug it already has is not a collision. AC3 again — the same slug in
    # another Team is none of this Team's business.
    taken = project.team.projects.kept.where.not(id: project.id).exists?(slug: slug)
    taken ? slug_taken(slug) : nil
  end

  def persist(changes)
    before = project.attributes.slice(*changes.keys.map(&:to_s))

    ApplicationRecord.transaction do
      project.update!(changes)

      AuditTrail.record(action: :project_updated, actor: actor, resource: project,
        before: before, after: project.attributes.slice(*changes.keys.map(&:to_s)))
    end

    Rails.logger.info(event: "project.updated", team_id: project.team.external_id,
      project_id: project.external_id, actor_id: actor.external_id,
      fields: changes.keys.map(&:to_s), result: "succeeded")

    Opanel::Result.success(project: project)
  end

  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug",
      suggestion: Project.suggest_slug(team: project.team, taken: slug, excluding: project.id))
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "project.updated", team_id: project.team&.external_id,
      project_id: project.external_id, actor_id: actor&.external_id,
      result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
