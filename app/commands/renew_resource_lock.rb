# Renews a resource lock's lease (M01-15, AC5).
#
# During operation execution, a worker maintains the lease by calling this periodically
# (heartbeat). The heartbeat resets lease_until to now() + TTL, extending the lock
# ownership. If the operation completes or the worker dies, the heartbeat stops and
# the lease expires.
#
# Only the current owner may renew (idempotent). Renewal fails with CONFLICT if:
# - The lock is not held (lease_until <= now()).
# - The owner differs.
# - The fencing token has advanced (another worker took over).
#
class RenewResourceLock
  LOCK_NOT_HELD = "This lock is no longer held by this worker."
  INVALID_LOCK = "The resource lock does not exist."
  INVALID_OWNER = "Only the lock owner may renew the lease."

  def self.call(lock:, worker_identity:, ttl_seconds: nil)
    new(lock: lock, worker_identity: worker_identity, ttl_seconds: ttl_seconds).call
  end

  def initialize(lock:, worker_identity:, ttl_seconds: nil)
    @lock = lock
    @worker_identity = worker_identity.to_s
    @ttl_seconds = ttl_seconds || Opanel::Configuration.fetch("OPANEL_RESOURCE_LOCK_TTL_SECONDS").to_i
  end

  def call
    return Opanel::Result.failure(code: "VALIDATION_ERROR", message: INVALID_LOCK) if lock.nil?
    return Opanel::Result.failure(code: "CONFLICT", message: INVALID_OWNER) unless lock.owner == worker_identity

    new_lease_until = Time.current + ttl_seconds.seconds

    # Renew only if still active and owner matches and token hasn't changed (idempotent).
    updated = lock.update(
      lease_until: new_lease_until,
      updated_at: Time.current
    )

    unless updated
      lock.reload
      return Opanel::Result.failure(code: "CONFLICT", message: LOCK_NOT_HELD) if lock.lease_until <= Time.current
      return Opanel::Result.failure(code: "CONFLICT", message: INVALID_OWNER) if lock.owner != worker_identity
      return Opanel::Result.failure(code: "CONFLICT", message: LOCK_NOT_HELD)
    end

    # Log renewal (AC9).
    log_event("lock.renewed", lock, worker_identity)

    Opanel::Result.success(lock)
  rescue StandardError => e
    Opanel::Result.failure(code: "RUNTIME_ERROR", message: e.message)
  end

  private

  attr_reader :lock, :worker_identity, :ttl_seconds

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
