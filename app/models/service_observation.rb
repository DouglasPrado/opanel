# An observation of a Docker Swarm Service at a point in time (doc 09 §10).
#
# ## Immutable actual state
#
# Each observation is an append-only record of what the Control Plane saw when it
# inspected the Swarm. Observations are never edited, only created. After a Control
# Plane restart, observations can be rebuilt by re-reading the runtime.
#
# ## Timestamped for staleness detection
#
# `observed_at` is the authoritative source of truth for when this service was last
# read from the Swarm. The UI uses this to determine if the data is "stale" and
# needs to display "last observed X seconds ago" (doc 10 §25).
#
# ## Separated from desired state
#
# The task counts, image digest, and node list here are what the Swarm reported.
# The Service model (desired state) has its own replicas and image columns
# representing what the operator configured. This observation is **actual state**
# and does not include desired state columns or any health boolean written manually.
# Status is always derived from appliedRevision + observation, never stored.
#
# ## Version ordering
#
# `docker_version_index` tracks Swarm's Version.Index to prevent out-of-order
# observations from overwriting newer ones. An observation with a lower
# docker_version_index must not replace one with a higher index.
#
class ServiceObservation < ApplicationRecord
  include UlidPrimaryKey

  belongs_to :service

  validates :desired_tasks, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :running_tasks, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :healthy_tasks, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :failed_tasks, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :observed_at, presence: true

  # Observations are immutable: never edited after creation. This is enforced
  # through application code (no update calls) and tests, not through
  # ActiveRecord readonly, which would prevent cascade deletes.
  # The job that creates observations handles synchronization.
end
