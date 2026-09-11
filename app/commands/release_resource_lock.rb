# Releases a resource lock after persisting the operation result (M01-15, AC5).
#
# An operation completes (SUCCEEDED, FAILED, etc.) and the worker releases the lock,
# allowing the next operation to acquire it. Release is idempotent: releasing an already
# released lock (or a lock held by another worker) is a no-op.
#
# Release **must** happen only after the Operation status and result are persisted.
# The Operation model ensures this with a guard flag (C3).
#
class ReleaseResourceLock
  LOCK_NOT_HELD = "This lock is not held by this worker."

  def self.call(lock:, worker_identity:)
    new(lock: lock, worker_identity: worker_identity).call
  end

  def initialize(lock:, worker_identity:)
    @lock = lock
    @worker_identity = worker_identity.to_s
  end

  def call
    return Opanel::Result.success(nil) if lock.nil?

    # Idempotent: only release if held by this worker.
    if lock.owner == worker_identity
      # Clear the lease by setting lease_until to the past.
      lock.update!(lease_until: Time.current - 1.second)

      log_event("lock.released", lock, worker_identity)
    elsif lock.lease_until <= Time.current
      # Lock expired; no action needed.
      log_event("lock.expired", lock, lock.owner)
    else
      # Lock held by another active worker; idempotently succeed.
      # (The caller releasing a lock they don't own is not an error — it's
      # a concurrent scenario where the lock was already taken over or released.)
    end

    Opanel::Result.success(nil)
  rescue StandardError => e
    Opanel::Result.failure(code: "RUNTIME_ERROR", message: e.message)
  end

  private

  attr_reader :lock, :worker_identity

  def log_event(event_type, lock, identity)
    Rails.logger.info(
      event: event_type,
      scope_key: lock.scope_key,
      owner: identity,
      fencing_token: lock.fencing_token,
      team_id: lock.team_id
    )
  end
end
