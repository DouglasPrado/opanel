# An instance of a Project running on a Cluster (doc 09 §5.2).
#
# ## The type field vs the entity name
#
# The column is named `type` because "environment" is already what we call this model.
# The enum-like values (PRODUCTION, HOMOLOGATION, etc.) are Types, not Statuses,
# and the database calls the column `type` to match the spec exactly.
#
# ## Status is observation, not a model state
#
# Like `Cluster`, `status` here records what the reconciler last saw. There is no
# stored boolean about health. A reader cannot tell "healthy" from "was healthy
# an hour ago" without looking at the age of the observation.
#
# ## Revision tracking
#
# `desired_revision` increments every time the operator changes intent (name, type,
# cluster, secrets config, etc.). `applied_revision` is where the reconciler got
# to, and it starts nil — it is set by `M01-18` (RefreshEnvironmentStatus).
#
# The database forbids `applied_revision > desired_revision`, and a meaningful
# change to a field that reconcilers care about must increment `desired_revision`
# at the Command layer, not here.
#
class Environment < ApplicationRecord
  include UlidPrimaryKey

  # The `type` column holds environment types (PRODUCTION, DEVELOPMENT, etc.),
  # not Rails' single-table inheritance. Disable STI to avoid conflicts.
  self.inheritance_column = nil

  # Types of Environment (doc 09 §5.2).
  PRODUCTION = "PRODUCTION"
  HOMOLOGATION = "HOMOLOGATION"
  DEVELOPMENT = "DEVELOPMENT"
  PREVIEW = "PREVIEW"
  CUSTOM = "CUSTOM"
  TYPES = [ PRODUCTION, HOMOLOGATION, DEVELOPMENT, PREVIEW, CUSTOM ].freeze

  # Status values (doc 09 §5.2, §17).
  PROVISIONING = "PROVISIONING"
  READY = "READY"
  DEGRADED = "DEGRADED"
  PAUSED = "PAUSED"
  DELETING = "DELETING"
  STATUSES = [ PROVISIONING, READY, DEGRADED, PAUSED, DELETING ].freeze

  # State machine: which statuses may follow which (doc 09 §17).
  TRANSITIONS = {
    PROVISIONING => [ READY, DEGRADED, PAUSED ].freeze,
    READY => [ DEGRADED, PAUSED, DELETING ].freeze,
    DEGRADED => [ READY, PAUSED, DELETING ].freeze,
    PAUSED => [ READY, PROVISIONING, DELETING ].freeze,
    DELETING => [].freeze
  }.freeze

  NAME_MAX_LENGTH = 120
  SLUG_MIN_LENGTH = 2
  SLUG_MAX_LENGTH = 63
  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  belongs_to :project
  belongs_to :cluster
  belongs_to :team
  has_many :services

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :slug, presence: true, format: { with: SLUG_FORMAT },
    length: { in: SLUG_MIN_LENGTH..SLUG_MAX_LENGTH }
  validates :type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :kept, -> { where(deleted_at: nil) }
  scope :active, -> { kept.where(status: READY) }

  # The tenancy boundary: environments accessible to this user through their Teams.
  # Like Project and Cluster, joined through the membership so suspension takes
  # effect immediately on the next query.
  scope :accessible_to, ->(user) {
    kept.joins(team: :team_members)
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
      .where(teams: { deleted_at: nil })
  }

  # Reuse the Team's slugify, same as Project and Cluster do.
  def self.slugify(value) = Team.slugify(value)

  # Suggest a free slug near the taken one, bounded to avoid scanning the whole index.
  # Same shape as `Project.suggest_slug` — two implementations would drift.
  SUGGESTION_ATTEMPTS = 8

  def self.suggest_slug(project:, taken:, excluding: nil)
    stem = taken.to_s.first(SLUG_MAX_LENGTH - 4).delete_suffix("-")
    scope = project.environments.kept
    scope = scope.where.not(id: excluding) if excluding

    candidate = (2..SUGGESTION_ATTEMPTS).lazy
      .map { |number| "#{stem}-#{number}" }
      .find { |option| !scope.exists?(slug: option) }

    candidate || "#{stem}-#{SecureRandom.hex(2)}"
  end

  # Type predicates (convenience).
  def production? = type == PRODUCTION
  def homologation? = type == HOMOLOGATION
  def development? = type == DEVELOPMENT
  def preview? = type == PREVIEW
  def custom? = type == CUSTOM

  # Status predicates (convenience).
  def provisioning? = status == PROVISIONING
  def ready? = status == READY
  def degraded? = status == DEGRADED
  def paused? = status == PAUSED
  def deleting? = status == DELETING

  # Whether `status` may become `target` (M01-04 principle: queries over conditionals).
  # Answers `false` rather than raising when the current status is unknown, because
  # the caller is a guard and guards that explode get rescued into `true`.
  def can_transition_to?(target)
    TRANSITIONS.fetch(status, []).include?(target)
  end

  # Derive a deterministic technical name for the overlay network from opaque IDs.
  # The name is stable; renaming a parent Project or Environment does not change it.
  # Pattern: net_<projectId>_<environmentId> (doc 08 §5).
  def technical_name
    Opanel::Ownership.technical_name_for(self)
  end
end
