# A Docker Swarm node as a product resource (doc 09 §4.2).
#
# ## Desired state lives here
#
# A Node represents what the operator knows and has configured about a Swarm node:
# its role, availability, and the addresses where it can be reached. This is
# **desired state**. What the runtime actually reports lives immutably in
# `NodeObservation` (doc 09 §10), taken at a point in time.
#
# ## `status` is denormalized from observation
#
# The `status` and `last_seen_at` columns here are copies of the most recent
# `NodeObservation`, kept for query efficiency. The authoritative observation
# always lives in the associated NodeObservation records.
#
# ## Stale observation detection
#
# The `last_seen_at` timestamp is when the Control Plane last looked at this node.
# If that timestamp is older than `FRESH_OBSERVATION_SECONDS`, the UI must show
# "last observed X seconds ago" rather than presenting the data as current
# (doc 10 §25).
class Node < ApplicationRecord
  include UlidPrimaryKey

  # States from doc 09 §4.2 and doc 17 (state machine).
  JOINING = "JOINING"
  READY = "READY"
  DEGRADED = "DEGRADED"
  DOWN = "DOWN"
  REMOVING = "REMOVING"

  STATUSES = [ JOINING, READY, DEGRADED, DOWN, REMOVING ].freeze

  # Roles from doc 09 §4.2.
  MANAGER = "MANAGER"
  WORKER = "WORKER"

  ROLES = [ MANAGER, WORKER ].freeze

  # Availability from doc 09 §4.2.
  ACTIVE = "ACTIVE"
  PAUSE = "PAUSE"
  DRAIN = "DRAIN"

  AVAILABILITIES = [ ACTIVE, PAUSE, DRAIN ].freeze

  # A reading older than this is stale (doc 10 §25). Same as Cluster's threshold.
  FRESH_OBSERVATION_SECONDS = 60

  belongs_to :cluster
  has_many :observations, class_name: "NodeObservation", foreign_key: :node_id,
    dependent: :destroy

  validates :swarm_node_id, presence: true
  validates :hostname, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :availability, inclusion: { in: AVAILABILITIES }
  validates :status, inclusion: { in: STATUSES }

  scope :kept, -> { where(deleted_at: nil) }

  # The tenancy boundary. A Node is accessible only through its Cluster → Team path.
  scope :accessible_to, ->(user) {
    kept.joins(cluster: { team: :team_members })
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
      .where(teams: { deleted_at: nil })
  }

  # Convenience predicates for state machine
  def manager? = role == MANAGER
  def worker? = role == WORKER

  def active? = availability == ACTIVE
  def paused? = availability == PAUSE
  def draining? = availability == DRAIN

  def joining? = status == JOINING
  def ready? = status == READY
  def degraded? = status == DEGRADED
  def down? = status == DOWN
  def removing? = status == REMOVING

  # Whether the observation is stale (doc 10 §25). A node with no observation
  # is considered stale — it has never been read from the runtime.
  # Staleness is derived from the authoritative NodeObservation.observed_at
  # rather than the denormalized Node.last_seen_at column (which exists for
  # query optimization only).
  def observation_stale?(now = Time.current)
    latest = latest_observation
    return true if latest.nil?

    now - latest.observed_at > FRESH_OBSERVATION_SECONDS
  end

  # Get the latest observation for this node.
  def latest_observation
    observations.order(observed_at: :desc).first
  end
end
