# A workload running in an Environment (doc 09 §5.3).
#
# ## Service type vs status
#
# The column is named `service_type` because "type" alone could be confused with
# Rails' single-table inheritance. Service types are WEB, WORKER, CRON, etc., and
# they are different from the service's operational status (RUNNING, DEGRADED, etc.).
#
# ## Status is observation, not a model state
#
# Like `Environment`, `status` here records what the reconciler last observed.
# There is no stored boolean about health. A reader cannot tell "healthy" from
# "was healthy an hour ago" without looking at the age of the observation.
#
# ## Revision tracking
#
# `desired_revision` increments every time the operator changes intent (replicas,
# image, resources, etc.). `applied_revision` is where the reconciler got to,
# and it starts nil — it is set by M01-18 (reconcilers).
#
# ## swarm_service_id is an observation, not a configuration
#
# It holds the Engine's own id for the Swarm Service this row converged to, and
# it is written by `ServiceReconciler` only after a re-inspection confirmed the
# resource (M01-18 AC10). It is never used to address the resource — ADR-0009 §5
# addresses an owned Service by its `com.opanel.service_id` label — so a stale
# value cannot send an operation to the wrong place. It is nil until the first
# convergence, and the database refuses two Services claiming the same one.
#
# ## Technical naming
#
# `technical_name` is deterministic and derived from IDs (doc 09 §5.3), but the
# product never uses it as a primary identifier. It is used to name the Swarm
# service at deployment time.
#
class Service < ApplicationRecord
  include UlidPrimaryKey

  # Service types (CRON, DATABASE, CACHE are added for completeness).
  WEB = "WEB"
  WORKER = "WORKER"
  CRON = "CRON"
  TASK = "TASK"
  DATABASE = "DATABASE"
  CACHE = "CACHE"
  TYPES = [ WEB, WORKER, CRON, TASK, DATABASE, CACHE ].freeze

  # Status values (doc 09 §17).
  DRAFT = "DRAFT"
  PROVISIONING = "PROVISIONING"
  RUNNING = "RUNNING"
  DEGRADED = "DEGRADED"
  STOPPED = "STOPPED"
  DELETING = "DELETING"
  STATUSES = [ DRAFT, PROVISIONING, RUNNING, DEGRADED, STOPPED, DELETING ].freeze

  # State machine: which statuses may follow which (doc 09 §17).
  TRANSITIONS = {
    DRAFT => [ PROVISIONING, DELETING ].freeze,
    PROVISIONING => [ RUNNING, DEGRADED, STOPPED, DELETING ].freeze,
    RUNNING => [ DEGRADED, STOPPED, DELETING ].freeze,
    DEGRADED => [ RUNNING, STOPPED, DELETING ].freeze,
    STOPPED => [ RUNNING, PROVISIONING, DELETING ].freeze,
    DELETING => [].freeze
  }.freeze

  NAME_MAX_LENGTH = 120
  SLUG_MIN_LENGTH = 2
  SLUG_MAX_LENGTH = 63
  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  belongs_to :environment
  belongs_to :team
  has_one :project, through: :environment

  # Operations for this Service. The association is loose (no foreign key) because
  # Operations reference any resource by type + id, not just Services.
  has_many :operations, -> { where(resource_type: "Service") }, foreign_key: :resource_id, dependent: :destroy

  # Observations of actual Swarm state. Append-only, immutable, timestamped.
  has_many :service_observations, dependent: :destroy

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :slug, presence: true, format: { with: SLUG_FORMAT },
    length: { in: SLUG_MIN_LENGTH..SLUG_MAX_LENGTH }
  validates :service_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :image_ref, presence: true
  validates :replicas, presence: true, numericality: { greater_than: 0, only_integer: true }

  scope :kept, -> { where(deleted_at: nil) }
  scope :active, -> { kept.where(status: RUNNING) }

  # The tenancy boundary: services accessible to this user through their Teams.
  # Joined through environment -> project -> team_member.
  scope :accessible_to, ->(user) {
    kept.joins(environment: { project: { team: :team_members } })
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
      .where(teams: { deleted_at: nil })
  }

  # Reuse the Team's slugify, same as Project and Environment do.
  def self.slugify(value) = Team.slugify(value)

  # Suggest a free slug near the taken one, bounded to avoid scanning the whole index.
  SUGGESTION_ATTEMPTS = 8

  def self.suggest_slug(environment:, taken:, excluding: nil)
    stem = taken.to_s.first(SLUG_MAX_LENGTH - 4).delete_suffix("-")
    scope = environment.services.kept
    scope = scope.where.not(id: excluding) if excluding

    candidate = (2..SUGGESTION_ATTEMPTS).lazy
      .map { |number| "#{stem}-#{number}" }
      .find { |option| !scope.exists?(slug: option) }

    candidate || "#{stem}-#{SecureRandom.hex(2)}"
  end

  # Type predicates (convenience).
  def web? = service_type == WEB
  def worker? = service_type == WORKER
  def cron? = service_type == CRON
  def task? = service_type == TASK
  def database? = service_type == DATABASE
  def cache? = service_type == CACHE

  # Status predicates (convenience).
  def draft? = status == DRAFT
  def provisioning? = status == PROVISIONING
  def running? = status == RUNNING
  def degraded? = status == DEGRADED
  def stopped? = status == STOPPED
  def deleting? = status == DELETING

  # Whether `status` may become `target`.
  def can_transition_to?(target)
    TRANSITIONS.fetch(status, []).include?(target)
  end

  # Derive a deterministic technical name from opaque IDs (doc 09 §5.3, AC3).
  # The name is stable; renaming a parent Project, Environment or Service does not
  # change it. The product never uses this as a primary identifier — it is metadata
  # for the Swarm Service resource.
  def technical_name
    Opanel::Ownership.technical_name_for(self)
  end
end
