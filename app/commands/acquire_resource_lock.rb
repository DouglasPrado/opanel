# Acquires a resource lock with a TTL and monotonic fencing token (M01-15).
#
# A lock serializes mutations on the same entity (serviceId, nodeId, etc.). Acquisition
# is idempotent and atomic: one row per scope, with TTL-based takeover and fencing tokens
# to prevent stale workers from applying obsolete results (C1, AC3, AC4).
#
# The operation uses a single atomic statement:
#
#   INSERT INTO resource_locks (...)
#   ON CONFLICT (scope_key) DO UPDATE
#      SET owner = EXCLUDED.owner,
#          lease_until = EXCLUDED.lease_until,
#          fencing_token = resource_locks.fencing_token + 1,
#          ...
#    WHERE resource_locks.lease_until <= NOW()
#   RETURNING fencing_token, owner, lease_until, (CASE WHEN old_owner != new_owner THEN true ELSE false END) as took_over
#
# Zero rows returned: lock is held by an active owner.
# One row returned: acquisition succeeded (new lock or takeover from expired).
#
# The successor must observe actual state before applying (C2, AC6): a separate
# `record_observation!` on the lease persists the observation, and fenced writes
# refuse a token whose acquisition took over unless an observation was recorded first.
#
class AcquireResourceLock
  LOCK_ALREADY_HELD = "This resource is currently locked by another worker."
  INVALID_SCOPE = "The scope key is invalid or empty."
  INVALID_TEAM = "The team is invalid or missing."
  INVALID_TTL = "The TTL is invalid or missing."

  def self.call(actor: nil, team:, scope_key:, ttl_seconds: nil)
    new(actor: actor, team: team, scope_key: scope_key, ttl_seconds: ttl_seconds).call
  end

  def initialize(actor: nil, team:, scope_key:, ttl_seconds: nil)
    @actor = actor
    @team = team
    @scope_key = scope_key.to_s.strip
    @ttl_seconds = ttl_seconds || Opanel::Configuration.fetch("OPANEL_RESOURCE_LOCK_TTL_SECONDS").to_i
  end

  def call
    # Validation.
    return Opanel::Result.failure(code: "VALIDATION_ERROR", message: INVALID_TEAM) if team.nil?
    return Opanel::Result.failure(code: "VALIDATION_ERROR", message: INVALID_SCOPE) if scope_key.blank?
    return Opanel::Result.failure(code: "VALIDATION_ERROR", message: INVALID_TTL) if ttl_seconds <= 0

    # Derive worker identity (AC10): never from client input.
    worker_identity = Opanel::WorkerIdentity.current
    lease_until = Time.current + ttl_seconds.seconds

    # Acquire atomically with takeover on expiry (C1).
    lock = acquire_with_takeover(worker_identity, lease_until)

    return Opanel::Result.failure(code: "CONFLICT", message: LOCK_ALREADY_HELD) if lock.nil?

    # Log acquisition (AC9).
    log_event("lock.acquired", lock, worker_identity)

    # Audit: privileged acquisition is audited (C3).
    audit_if_privileged("resource.lock.acquired")

    Opanel::Result.success(lock)
  rescue StandardError => e
    # Log the exception with its class and context; never expose SQL or stack
    Rails.logger.error(
      event: "lock.acquisition_failed",
      error_class: e.class.name,
      error_message: e.message.lines.first,
      scope_key: scope_key,
      team_id: team.id
    )
    Opanel::Result.failure(code: "RUNTIME_ERROR", message: "Failed to acquire lock")
  end

  private

  attr_reader :actor, :team, :scope_key, :ttl_seconds

  def acquire_with_takeover(worker_identity, lease_until)
    # One atomic INSERT ... ON CONFLICT DO UPDATE with WHERE clause (C1).
    # Returns the acquired lock with took_over flag set if takeover occurred.
    # Zero rows returned means the lock is held by an active owner.

    lock_id = Opanel::Identifier.generate

    sql = <<~SQL
      INSERT INTO resource_locks (
        id, team_id, scope_key, owner, lease_until, fencing_token,
        created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6,
        now() at time zone 'UTC', now() at time zone 'UTC'
      )
      ON CONFLICT (scope_key) DO UPDATE
        SET owner = EXCLUDED.owner,
            lease_until = EXCLUDED.lease_until,
            fencing_token = resource_locks.fencing_token + 1,
            updated_at = now() at time zone 'UTC'
        WHERE resource_locks.lease_until <= now()
      RETURNING
        id, team_id, scope_key, owner, lease_until, fencing_token,
        created_at, updated_at, (xmax <> 0) AS took_over
    SQL

    result = ResourceLock.connection.exec_query(
      sql,
      "AcquireResourceLock",
      [ lock_id, team.id, scope_key, worker_identity, lease_until, 0 ]
    )

    return nil if result.empty?

    # exec_query returns a result object; access columns by name
    row_hash = result.first

    # Capture took_over from the RETURNING clause before building the model
    # (xmax <> 0 means the row was updated, not inserted).
    took_over = row_hash["took_over"] == "t" || row_hash["took_over"] == true

    # Map the result to a model instance (C2, AC6: took_over flag).
    # Build from RETURNING data without a redundant database lookup.
    rl = ResourceLock.instantiate(row_hash.except("took_over"))

    # Store flags for use in fenced writes (C2).
    rl.define_singleton_method(:took_over?) { took_over }
    rl.define_singleton_method(:recorded_observation?) { false }

    rl
  end

  def log_event(event_type, lock, worker_identity)
    Rails.logger.info(
      event: event_type,
      scope_key: scope_key,
      owner: worker_identity,
      fencing_token: lock.fencing_token,
      team_id: team.id
    )
  end

  def audit_if_privileged(action)
    return unless actor

    AuditTrail.record(
      actor: actor,
      action: action,
      resource: team,
      result: "SUCCESS",
      after: { scope_key: scope_key, fencing_token: "present" }
    )
  end
end
