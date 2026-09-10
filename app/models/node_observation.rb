# An observation of a Docker Swarm node at a point in time (doc 09 §10).
#
# ## Immutable actual state
#
# Each observation is an append-only record of what the Control Plane saw when it
# inspected the Swarm. Observations are never edited, only created. After a
# Control Plane restart, observations can be rebuilt by re-reading the runtime.
#
# ## Timestamped for staleness detection
#
# `observed_at` is the authoritative source of truth for when this node was last
# read from the Swarm. The UI uses this to determine if the data is "stale" and
# needs to display "last observed X seconds ago" (doc 10 §25).
#
# ## Separated from desired state
#
# The `status`, `availability`, and resource information here is what the Swarm
# reported. The Node model (desired state) has its own availability and role
# columns representing what the operator configured. This observation is **actual
# state** and does not include desired state columns.
class NodeObservation < ApplicationRecord
  include UlidPrimaryKey

  # States from doc 09 §4.2 — what the node reported being in.
  JOINING = "JOINING"
  READY = "READY"
  DEGRADED = "DEGRADED"
  DOWN = "DOWN"
  REMOVING = "REMOVING"

  STATUSES = [ JOINING, READY, DEGRADED, DOWN, REMOVING ].freeze

  # Availability from doc 09 §4.2 — what the node reported being set to.
  ACTIVE = "ACTIVE"
  PAUSE = "PAUSE"
  DRAIN = "DRAIN"

  AVAILABILITIES = [ ACTIVE, PAUSE, DRAIN ].freeze

  belongs_to :node

  validates :status, inclusion: { in: STATUSES }
  validates :availability, inclusion: { in: AVAILABILITIES }, allow_nil: true
  validates :observed_at, presence: true

  # Observations are immutable: never edited after creation. This is enforced
  # through application code (no update calls) and tests, not through
  # ActiveRecord readonly, which would prevent cascade deletes.
  # The job that creates observations handles synchronization.
end
