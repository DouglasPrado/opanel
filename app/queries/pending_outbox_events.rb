# frozen_string_literal: true

# Query: find unpublished OutboxEvents ready to publish (M01-14 dispatcher, doc 07 §10).
#
# The dispatcher publishes events in order to the queue, then marks them published.
# This query returns the oldest unpublished events up to a batch size limit.
#
class PendingOutboxEvents
  def initialize(batch_size: Opanel::Configuration.outbox_dispatcher_batch_size)
    @batch_size = batch_size
  end

  # @return [ActiveRecord::Relation] unpublished events ordered by occurred_at (oldest first)
  def call
    OutboxEvent.unpublished
      .ordered
      .limit(@batch_size)
  end
end
