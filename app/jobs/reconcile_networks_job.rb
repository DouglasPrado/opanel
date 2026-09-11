# Periodic network reconciliation sweep (doc 07 §11.2, M01-17 AC10).
#
# The reconciler is triggered both by Operations (event-driven) and by this sweep
# (periodic). The sweep ensures correctness even if no Operations were enqueued.
#
class ReconcileNetworksJob < ApplicationJob
  queue_as :system
  set(wait: 5.seconds)  # Brief wait to allow batching

  def perform
    # Find all active environments with networks that need reconciliation.
    # For now, reconcile all active environments; later, filter by trigger.
    Environment.active.includes(:network, :cluster, :team).find_each do |env|
      next unless env.network

      NetworkReconciler.call(
        environment: env,
        trigger: ReconciliationRun::PERIODIC
      )
    rescue StandardError => e
      Rails.logger.error(
        event: "reconcile_networks_job.failed",
        environment_id: env.external_id,
        error: e.message,
        backtrace: e.backtrace.first(5)
      )
      # Continue with the next environment; do not re-raise.
    end
  end
end
