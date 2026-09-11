# frozen_string_literal: true

# Command: PublishPendingOutboxEvents — publish OutboxEvents to the queue (M01-14, doc 07 §10).
#
# The dispatcher is called periodically by PublishOutboxEventsJob. It reads unpublished
# OutboxEvents in order (by occurred_at), validates their schemaVersion, publishes to
# the appropriate queue, and marks them published.
#
# If the broker is unavailable, events remain unpublished in the database (durability).
# If an event's schemaVersion is unknown, it is skipped (not published, not deleted, logged).
#
class PublishPendingOutboxEvents
  class PublishingError < StandardError; end

  def initialize(batch_size: Opanel::Configuration.outbox_dispatcher_batch_size)
    @batch_size = batch_size
  end

  def call
    events = PendingOutboxEvents.new(batch_size: @batch_size).call

    events.each do |event|
      # Validate event schema before publishing (AC8).
      # Checks both the column schema_version and the payload's schemaVersion.
      valid, error = Opanel::OperationPayload.event_valid?(event.event_type, event.schema_version, event.payload)
      unless valid
        # Skip and log; do not publish, do not delete.
        log_event(
          event: "outbox.event.schema_unknown",
          result: "skipped",
          outbox_event_id: event.id,
          event_type: event.event_type,
          schema_version: event.schema_version,
          reason: error
        )
        next
      end

      # Determine the logical queue for this event.
      queue = Opanel::Queues.for_event_type(event.event_type)

      begin
        # Atomically enqueue the job and mark the event published.
        # Because SolidQueue lives in the primary database (config/application.rb:96),
        # both statements roll back together. If the transaction commits, both are durable.
        # If it rolls back (e.g., mark_published! fails), the SolidQueue::Job row is not created.
        # On retry, a later dispatcher pass publishes again: at-least-once, never at-most-once.
        # Duplicate publishes are acceptable per AC4: the inbox dedup of the consumer
        # ensures duplicate logical effects do not occur (doc 07 §22, "processar duas vezes
        # com efeito duplicado não é"; publicar duas vezes é aceitável).
        ActiveRecord::Base.transaction do
          publish_to_queue(queue, event)
          event.mark_published!
        end

        log_event(
          event: "outbox.event.published",
          result: "ok",
          outbox_event_id: event.id,
          event_type: event.event_type,
          queue: queue
        )
      rescue StandardError => e
        log_event(
          event: "outbox.event.publish_failed",
          result: "error",
          outbox_event_id: event.id,
          event_type: event.event_type,
          error_class: e.class.name
        )
        # Do not raise: continue publishing remaining events.
        # The event stays unpublished for the next sweep.
      end
    end
  end

  private

  # Publish an event to its logical queue.
  # @param queue [String] the queue name
  # @param event [OutboxEvent] the event to publish
  # @raise [StandardError] if publishing fails (e.g., broker unavailable)
  def publish_to_queue(queue, event)
    # SolidQueue implementation: enqueue a job that consumes the event.
    # The payload carries the event ID, not the full event body (immutable, already in DB).
    SolidQueue::Job.create!(
      queue_name: queue,
      class_name: "OutboxEventConsumerJob",
      arguments: [ event.id ],
      created_at: Time.current.utc,
      scheduled_at: Time.current.utc
    )
  end

  def log_event(event:, result:, **fields)
    # Log rejected schemas at warn level (operational anomaly for operator visibility).
    # Published and failed events log at info level (normal operational events).
    level = event.include?("schema_unknown") ? :warn : :info
    Rails.logger.send(level,
      {
        event: event,
        result: result
      }.merge(fields)
    )
  end
end
