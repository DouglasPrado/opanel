# frozen_string_literal: true

# Queue backpressure signal: detect when the outbox is backlogging (M01-14, AC7).
#
# When the outbox backlog exceeds the configured high-water mark, callers can check
# this signal to defer Operation creation instead of rejecting it. The Operation still
# persists in Desired State, but next_attempt_at is pushed forward to allow the dispatcher
# to drain the queue first.
#
# This is not throttling or rate limiting; it is deferral. Nothing is ever lost or rejected.
#
module Opanel::QueueBackpressure
  # Check if backpressure is active: unpublished events exceed high-water mark.
  # @return [Boolean] true if backpressure is active
  def self.active?
    unpublished_count = OutboxEvent.unpublished.count
    threshold = Opanel::Configuration.queue_backpressure_high_water_mark

    unpublished_count >= threshold
  end

  # The amount of deferral to apply when backpressure is active.
  # @return [Integer] seconds to defer next_attempt_at
  def self.deferral_delay_seconds
    Opanel::Configuration.queue_backpressure_delay_seconds
  end

  # Calculate the deferred next_attempt_at when backpressure is active.
  # @return [Time] when the operation should be attempted
  def self.deferred_next_attempt_at
    Time.current.utc + deferral_delay_seconds.seconds
  end
end
