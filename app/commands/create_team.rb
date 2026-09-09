# Creates a Team and makes its creator the OWNER (doc 09 §3.2, AC1).
#
# The two rows are written in **one transaction**, and they have to be: a Team
# with no OWNER is refused by `fk_teams_active_owner_membership`, and the key is
# deferred precisely so this pair can be written in either order and judged at
# COMMIT. There is no window in which a Team exists without an owner, and none in
# which a membership points at a Team that was rolled back.
#
# No network call happens inside the transaction, and nothing here decides
# authorization beyond "there is an authenticated actor" — the first member of a
# Team is its owner by definition, which is why this Command has no Policy and
# M01-04 will not give it one.
class CreateTeam
  NAME_REQUIRED = "Enter a name for the team."
  NAME_TOO_LONG = "That name is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "A URL name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That URL name is already taken."

  # How many `-2`, `-3` … variants to probe before falling back to something
  # random. Bounded on purpose: a suggestion is a convenience, and an unbounded
  # scan of a unique index is a way to make Team creation slow for everybody once
  # a popular name exists.
  SUGGESTION_ATTEMPTS = 8

  def self.call(actor:, name:, slug: nil)
    new(actor: actor, name: name, slug: slug).call
  end

  def initialize(actor:, name:, slug: nil)
    @actor = actor
    @name = name.to_s.strip
    @requested_slug = slug.to_s.strip.downcase.presence
  end

  def call
    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if name.blank?
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if name.length > Team::NAME_MAX_LENGTH

    slug = resolved_slug
    return failure("VALIDATION_ERROR", slug_error, field: "slug") if slug.nil?

    return slug_taken(slug) if taken?(slug)

    persist(slug)
  rescue ActiveRecord::RecordNotUnique
    # The check-then-insert window is real; the unique index is what closes it.
    # Losing the race must be indistinguishable from finding the slug taken, or
    # the two paths drift and only one of them stays correct.
    slug_taken(resolved_slug)
  end

  private

  attr_reader :actor, :name, :requested_slug

  def persist(slug)
    team = nil
    membership = nil

    ApplicationRecord.transaction do
      team = Team.create!(name: name, slug: slug, owner_user_id: actor.id, status: "ACTIVE")
      membership = TeamMember.create!(team: team, user: actor, role: "OWNER",
        status: "ACTIVE", joined_at: Time.current)
    end

    Rails.logger.info(event: "team.created", team_id: team.external_id,
      actor_id: actor.external_id, result: "succeeded")

    Opanel::Result.success(team: team, membership: membership)
  end

  def resolved_slug
    @resolved_slug ||= requested_slug || Team.slugify(name)
  end

  def slug_error
    requested_slug ? SLUG_INVALID : SLUG_UNUSABLE
  end

  def taken?(slug)
    return true unless slug.match?(Team::SLUG_FORMAT)

    Team.kept.exists?(slug: slug)
  end

  # The Story's failure table asks for "validação inline com sugestão; nunca
  # colisão silenciosa". The suggestion is part of the failure rather than a
  # second round trip.
  def slug_taken(slug)
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug", suggestion: suggestion_for(slug))
  end

  def suggestion_for(slug)
    stem = slug.to_s.first(Team::SLUG_MAX_LENGTH - 4).delete_suffix("-")

    candidate = (2..SUGGESTION_ATTEMPTS).lazy
      .map { |number| "#{stem}-#{number}" }
      .find { |option| !Team.kept.exists?(slug: option) }

    candidate || "#{stem}-#{SecureRandom.hex(2)}"
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "team.created", actor_id: actor&.external_id, result: "rejected",
      reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
