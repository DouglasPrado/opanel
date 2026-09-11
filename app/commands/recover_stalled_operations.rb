# frozen_string_literal: true

# Command: RecoverStalledOperations — recover Operations whose messages were lost (M01-14, doc 07 §22).
#
# Periodically called by RecoverStalledOperationsJob. Finds Operations that are stuck
# (QUEUED with stale next_attempt_at, or RUNNING without recent heartbeat), marks them
# as STALLED for observability, and re-enqueues them (pushes next_attempt_at into future).
#
# Uses SELECT ... FOR UPDATE SKIP LOCKED to ensure concurrent sweeps do not process
# the same operations twice (AC11, AGENT_RULES "Reconciliation").
#
# Never changes a FAILED operation's status: a failed operation requires explicit
# retry through the API, never auto-recovery (AC6, RB-03).
#
class RecoverStalledOperations
  def initialize(
    batch_size: Opanel::Configuration.recovery_sweep_batch_size,
    heartbeat_threshold: Opanel::Configuration.recovery_sweep_heartbeat_threshold
  )
    @batch_size = batch_size
    @heartbeat_threshold = heartbeat_threshold
  end

  def call
    operations = StalledOperations.new(
      batch_size: @batch_size,
      heartbeat_threshold: @heartbeat_threshold
    ).call

    operations.each do |operation|
      # Mark the operation as STALLED with a reason for observability.
      reason = determine_stalled_reason(operation)
      operation.mark_stalled!(reason)

      # Release any lock held by this operation (M01-15, AC7: TTL guarantees release).
      release_orphaned_lock(operation) if operation.lease_owner.present?

      # Re-enqueue by pushing next_attempt_at into the future.
      # The operation status remains QUEUED/RUNNING; only the timing changes.
      # This allows the dispatcher to pick it up again after the deferral window.
      deferral_delay_seconds = ENV.fetch("OPANEL_RECOVERY_SWEEP_QUEUED_THRESHOLD_SECONDS", "300").to_i
      operation.update!(next_attempt_at: Time.current.utc + deferral_delay_seconds.seconds)

      log_event(
        event: "recovery.operation_recovered",
        result: "ok",
        operation_id: operation.id,
        team_id: operation.team_id,
        reason: reason,
        status: operation.status
      )
    end
  end

  private

  # Release any orphaned lock held by a stalled operation (M01-15, AC7).
  # When a worker dies, the TTL guarantees the lock expires eventually.
  # The recovery sweep logs the detection for observability.
  def release_orphaned_lock(operation)
    # The lock scope key is typically the resource_id (serviceId, nodeId, etc.).
    # In M01-15, locks are per-scope per-team, and the lock row outlives operations.
    # If the lock expired or was taken over, nothing to do. If still active, mark expired.
    lock = ResourceLock.where(
      team_id: operation.team_id,
      owner: operation.lease_owner
    ).first

    return unless lock&.lease_until&.present?

    # Set lease_until to the past to release immediately, allowing new acquisition.
    lock.update!(lease_until: Time.current - 1.second)

    log_event(
      event: "recovery.lock_released_orphaned",
      result: "ok",
      operation_id: operation.id,
      team_id: operation.team_id,
      scope_key: lock.scope_key,
      fencing_token: lock.fencing_token
    )
  rescue StandardError => e
    log_event(
      event: "recovery.lock_release_failed",
      result: "error",
      operation_id: operation.id,
      team_id: operation.team_id,
      reason: e.message
    )
  end

  # Determine why an operation is stalled.
  # @param operation [Operation] the operation to evaluate
  # @return [String] the reason (e.g., "no_progress_since_queued")
  def determine_stalled_reason(operation)
    case operation.status
    when Operation::QUEUED
      "no_progress_since_queued"
    when Operation::RUNNING
      "no_heartbeat"
    else
      "unknown"
    end
  end

  def log_event(event:, result:, **fields)
    Rails.logger.info(
      {
        event: event,
        result: result
      }.merge(fields)
    )
  end
end
