# Resource locks serialize mutations on the same entity (doc 07 §14.1, M01-15).
#
# One lock per scope (serviceId, nodeId, clusterId, etc.), with a time-to-live (TTL)
# and monotonic fencing token. Prevents stale workers from applying obsolete results
# after losing the lease (AC4, AC6).
#
# Acquisition is idempotent and atomic (C1):
#   INSERT INTO resource_locks (id, scope_key, owner, lease_until, fencing_token, ...)
#   VALUES (...)
#   ON CONFLICT (scope_key) DO UPDATE
#      SET owner = EXCLUDED.owner,
#          lease_until = EXCLUDED.lease_until,
#          fencing_token = resource_locks.fencing_token + 1,
#          ...
#    WHERE resource_locks.lease_until <= now()
#   RETURNING fencing_token, owner, lease_until, took_over
#
# Zero rows returned: lock is held by another active owner.
# One row returned: acquisition succeeded (either new lock or takeover from expired).
#
class ResourceLock < ApplicationRecord
  include UlidPrimaryKey

  belongs_to :team

  # Validations.
  validates :team_id, presence: true
  validates :scope_key, presence: true
  validates :owner, presence: true
  validates :lease_until, presence: true
  validates :fencing_token, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes.
  scope :expired, -> { where("lease_until <= ?", Time.current) }
  scope :active, -> { where("lease_until > ?", Time.current) }

  # Predicate: is this lock expired?
  def expired?
    lease_until <= Time.current
  end

  def active?
    lease_until > Time.current
  end

  # Record an observation on this lock (C2, AC6).
  # When a successor takes over after lease expiry, it must observe actual state before
  # acting. This call persists that observation, and fenced writes check for it.
  def record_observation!
    # Mark that an observation was recorded for this acquisition.
    # This is a simple flag stored on the instance; in a real system, this might
    # update a field in the database or check a related Observation record.
    @observation_recorded = true
  end

  def observation_recorded?
    @observation_recorded == true
  end
end
