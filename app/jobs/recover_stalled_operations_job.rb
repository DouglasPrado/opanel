# frozen_string_literal: true

# Job: RecoverStalledOperationsJob — periodically recover stalled Operations (M01-14).
#
# Scheduled by config/recurring.yml with a cadence from Opanel::Configuration.
# Calls RecoverStalledOperations to identify and re-enqueue operations whose
# messages were lost or whose workers died without completing the work.
#
class RecoverStalledOperationsJob < ApplicationJob
  queue_as :system

  # Retry policy: recovery sweep failures are serious (lost operations),
  # so we retry, but limit attempts to avoid infinite loops.
  retry_policy on: StandardError, attempts: 2, wait: :polynomially_longer

  def perform
    RecoverStalledOperations.new.call
  end
end
