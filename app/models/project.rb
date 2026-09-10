# The logical product of a Team (doc 09 §5.1).
#
# A Project is what the operator came to build. It owns no infrastructure: where
# something runs is the Environment's answer, and doc 01 §5.1 makes that a
# structural invariant rather than a preference — there is no `cluster_id` on this
# table, and adding one would make the wrong hierarchy true in the schema.
#
# The slug is a name in a URL: human, editable, unique among the Team's living
# Projects, and **never** a foreign key (AC7, doc 09 §19). Everything that points
# at a Project points at its ULID, so renaming one is a rename and nothing else.
class Project < ApplicationRecord
  include UlidPrimaryKey

  # doc 09 §5.1. `DELETING` exists in the database and is unreachable from here:
  # entering it means reconciling the runtime first, which is `M02-09`. In M01 a
  # Project archives, and archiving is reversible.
  ACTIVE = "ACTIVE"
  ARCHIVED = "ARCHIVED"
  DELETING = "DELETING"
  STATUSES = [ ACTIVE, ARCHIVED, DELETING ].freeze

  # The transitions this Milestone can perform, as data rather than as a chain of
  # conditionals.
  #
  # Both terminal states have an empty edge list, and neither is an oversight.
  # Leaving `DELETING` is not a decision the Control Plane makes alone — the
  # runtime has to be gone first, which is `M02-09`. Leaving `ARCHIVED` is a
  # restore, and this Story's scope names three Commands, none of which is one.
  #
  # An edge nothing can traverse is worse than a missing edge: it reads as a
  # capability, it makes `can_transition_to?` answer true for something that
  # cannot happen, and the branch guarding it can never be seen failing. That is
  # the shape of `M01-04`'s open finding about `:out_of_scope`, and repeating it
  # deliberately would be worse than having caused it.
  TRANSITIONS = {
    ACTIVE => [ ARCHIVED ].freeze,
    ARCHIVED => [].freeze,
    DELETING => [].freeze
  }.freeze

  NAME_MAX_LENGTH = 120
  DESCRIPTION_MAX_LENGTH = 2000
  SLUG_MIN_LENGTH = 2
  SLUG_MAX_LENGTH = 63
  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  belongs_to :team
  has_many :environments, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :slug, presence: true, format: { with: SLUG_FORMAT },
    length: { in: SLUG_MIN_LENGTH..SLUG_MAX_LENGTH }
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  scope :kept, -> { where(deleted_at: nil) }
  scope :active, -> { kept.where(status: ACTIVE) }

  # The tenancy boundary, in the query (Annex C §7.3). `TenantScope` delegates
  # here rather than restating it, for the same reason `Team.accessible_to`
  # exists: two definitions of "which Projects may this user see" eventually
  # disagree, and the one that is wrong is the one nobody is reading.
  #
  # Joined through the membership, so a suspension takes effect on the very next
  # query with nothing to invalidate.
  scope :accessible_to, ->(user) {
    kept.joins(team: :team_members)
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
      .where(teams: { deleted_at: nil })
  }

  # Reuses `Team.slugify` instead of copying it: the two slugs answer to the same
  # CHECK, the same length bounds and the same alphabet, and a second
  # implementation would drift the moment one of them is corrected.
  def self.slugify(value) = Team.slugify(value)

  # A free slug near the one that was taken, for the inline suggestion the
  # Story's failure table asks for (*"validação inline com sugestão"*).
  #
  # On the model rather than in a Command because both `CreateProject` and
  # `UpdateProject` need it and they must offer the *same* alternative — a second
  # implementation would eventually suggest something the other rejects.
  #
  # Bounded on purpose: a suggestion is a convenience, and an unbounded scan of a
  # unique index is a way to make creation slow for everybody once a popular name
  # exists. Past the probes it falls back to entropy, which always terminates.
  SUGGESTION_ATTEMPTS = 8

  def self.suggest_slug(team:, taken:, excluding: nil)
    stem = taken.to_s.first(SLUG_MAX_LENGTH - 4).delete_suffix("-")
    scope = team.projects.kept
    scope = scope.where.not(id: excluding) if excluding

    candidate = (2..SUGGESTION_ATTEMPTS).lazy
      .map { |number| "#{stem}-#{number}" }
      .find { |option| !scope.exists?(slug: option) }

    candidate || "#{stem}-#{SecureRandom.hex(2)}"
  end

  def active? = status == ACTIVE
  def archived? = status == ARCHIVED
  def deleting? = status == DELETING

  # Whether `status` may become `target`. Total: an unknown status answers false
  # rather than raising, because the caller is a guard and a guard that explodes
  # is a guard that gets rescued into `true` somewhere.
  def can_transition_to?(target)
    TRANSITIONS.fetch(status, []).include?(target)
  end
end
