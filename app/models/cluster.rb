# A Docker Swarm as a product resource (doc 09 §4.1).
#
# ## The status is an observation, not a claim
#
# doc 06 §14.1 spends a section rejecting the idea that a cluster is Ready or Not
# Ready, and AC11 turns that into a rule: the status here is *the last thing the
# runtime said*, and `observed_at` is when it said it. There is no stored boolean
# about health, and a reader that cannot see the age of a reading cannot tell
# "healthy" from "was healthy an hour ago". The database refuses a non-PROVISIONING
# status with no timestamp (`clusters_observed_status_has_a_timestamp`).
#
# ## `team_id` is NOT NULL
#
# `SC-12`, resolved restrictively for this pack: doc 09 §4.1 allows a null owner
# for an explicitly modelled system cluster, and a nullable owner is an
# authorization path with no tenancy boundary. There is no system cluster here,
# and adding one needs its own ADR.
class Cluster < ApplicationRecord
  include UlidPrimaryKey

  # doc 09 §4.1. `MAINTENANCE` and `DELETING` are declared because the column's
  # CHECK carries them and a state the database accepts should have a name in the
  # code; neither is reachable from this Milestone.
  PROVISIONING = "PROVISIONING"
  READY = "READY"
  DEGRADED = "DEGRADED"
  MAINTENANCE = "MAINTENANCE"
  UNREACHABLE = "UNREACHABLE"
  DELETING = "DELETING"

  STATUSES = [ PROVISIONING, READY, DEGRADED, MAINTENANCE, UNREACHABLE, DELETING ].freeze

  # The transitions this Milestone can perform. The Story names
  # `PROVISIONING → READY | DEGRADED` and `READY ↔ DEGRADED ↔ UNREACHABLE`.
  #
  # `MAINTENANCE` and `DELETING` have no edges here, and that is not an
  # oversight: entering maintenance is an administrative operation nothing in M01
  # performs, and `DELETING` needs the runtime drained first. An edge nothing can
  # traverse reads as a capability and can never be seen failing.
  TRANSITIONS = {
    PROVISIONING => [ READY, DEGRADED, UNREACHABLE ].freeze,
    READY => [ DEGRADED, UNREACHABLE ].freeze,
    DEGRADED => [ READY, UNREACHABLE ].freeze,
    UNREACHABLE => [ READY, DEGRADED ].freeze,
    MAINTENANCE => [].freeze,
    DELETING => [].freeze
  }.freeze

  NAME_MAX_LENGTH = 120
  SLUG_MIN_LENGTH = 2
  SLUG_MAX_LENGTH = 63
  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  # Docker's own shape for a Swarm id: lowercase base36, 25 characters in
  # practice. Bounded rather than pinned so an Engine that changes the length
  # does not make every Cluster unwritable.
  SWARM_ID_FORMAT = /\A[a-z0-9]{20,32}\z/

  # A reading older than this is stale: the UI must say "last observed …" rather
  # than present it as current (doc 10 §25).
  FRESH_OBSERVATION_SECONDS = 60

  belongs_to :team

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :slug, presence: true, format: { with: SLUG_FORMAT },
    length: { in: SLUG_MIN_LENGTH..SLUG_MAX_LENGTH }
  validates :status, inclusion: { in: STATUSES }
  validates :swarm_id, format: { with: SWARM_ID_FORMAT }, allow_nil: true,
    uniqueness: { conditions: -> { where.not(swarm_id: nil) } }

  scope :kept, -> { where(deleted_at: nil) }

  # The tenancy boundary, in the query (Annex C §7.3). Same shape as `Project`,
  # and joined through the membership so a suspension takes effect on the next
  # query with nothing to invalidate.
  scope :accessible_to, ->(user) {
    kept.joins(team: :team_members)
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
      .where(teams: { deleted_at: nil })
  }

  # One slug function for the whole product. See `Project.slugify`.
  def self.slugify(value) = Team.slugify(value)

  def provisioning? = status == PROVISIONING
  def ready? = status == READY
  def degraded? = status == DEGRADED
  def unreachable? = status == UNREACHABLE

  def can_transition_to?(target) = TRANSITIONS.fetch(status, []).include?(target)

  # Whether the Swarm has been established at all. Asked of the observed id
  # rather than of the status, because a Cluster that was READY an hour ago and
  # is UNREACHABLE now still has one.
  def bootstrapped? = swarm_id.present?

  # doc 10 §25's stale state, decided here so every screen agrees. `nil`
  # `observed_at` is not "fresh" — it is a Cluster nothing has looked at.
  def observation_stale?(now = Time.current)
    return true if observed_at.nil?

    now - observed_at > FRESH_OBSERVATION_SECONDS
  end
end
