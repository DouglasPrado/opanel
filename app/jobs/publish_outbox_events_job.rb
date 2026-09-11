# frozen_string_literal: true

# Job: PublishOutboxEventsJob — periodically publish unpublished OutboxEvents (M01-14).
#
# Scheduled by config/recurring.yml with a cadence from Opanel::Configuration.
# Calls PublishPendingOutboxEvents to read, validate, and publish events.
#
class PublishOutboxEventsJob < ApplicationJob
  queue_as :system

  # Retry policy: transient network/broker errors warrant retry,
  # but if publishing fails, we want visibility (not silent retries).
  retry_policy on: StandardError, attempts: 3, wait: :polynomially_longer

  def perform
    PublishPendingOutboxEvents.new.call
  end
end
