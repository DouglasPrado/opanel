# frozen_string_literal: true

# Query: find Operations without progress (QUEUED or RUNNING) ready for recovery (M01-14 sweep).
#
# The recovery sweep re-enqueues Operations whose messages were lost or whose workers
# died without completing the work. This query identifies candidates:
#
# - QUEUED operations whose next_attempt_at is in the past (no worker picked them up).
# - RUNNING operations whose last update is older than a heartbeat threshold (worker died).
#
# The query uses SELECT ... FOR UPDATE SKIP LOCKED to ensure concurrent sweeps do not
# process the same operations twice (AC11, doc 07 §22, AGENT_RULES "Reconciliation").
#
class StalledOperations
  def initialize(
    batch_size: Opanel::Configuration.recovery_sweep_batch_size,
    heartbeat_threshold: Opanel::Configuration.recovery_sweep_heartbeat_threshold
  )
    @batch_size = batch_size
    @heartbeat_threshold = heartbeat_threshold
  end

  # @return [ActiveRecord::Relation] stalled operations, locked and ready for retry
  def call
    Operation
      .where(stalled_at: nil) # Exclude operations already marked stalled
      .where.not(status: Operation::TERMINAL_STATUSES)
      .where(
        "status = ? AND next_attempt_at < ? OR status = ? AND updated_at < ?",
        Operation::QUEUED, Time.current.utc,
        Operation::RUNNING, @heartbeat_threshold
      )
      .lock("FOR UPDATE SKIP LOCKED") # Concurrent sweeps skip locked rows (C3, AC11)
      .order(:created_at)
      .limit(@batch_size)
  end
end
