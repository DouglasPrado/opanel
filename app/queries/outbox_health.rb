# frozen_string_literal: true

# Query: observe the health of the outbox and queue (M01-14 metrics, AC2, AC10).
#
# Provides metrics for observability when the broker is unavailable:
# - oldest_event_age_seconds: how long the oldest unpublished event has been waiting.
# - unpublished_count: total count of events waiting to publish.
#
# These metrics allow an alert to fire when events back up (e.g., broker down for 5+ minutes).
#
class OutboxHealth
  # @return [Hash] health metrics
  def call
    oldest = OutboxEvent.unpublished.order(:occurred_at).first

    if oldest
      age_seconds = (Time.current.utc - oldest.occurred_at).to_i
      {
        oldest_event_age_seconds: age_seconds,
        oldest_event_id: oldest.id,
        oldest_event_type: oldest.event_type,
        unpublished_count: OutboxEvent.unpublished.count
      }
    else
      {
        oldest_event_age_seconds: nil,
        oldest_event_id: nil,
        oldest_event_type: nil,
        unpublished_count: 0
      }
    end
  end
end
