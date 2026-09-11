# frozen_string_literal: true

# An InboxEvent records received external messages for deduplication (doc 07 §10.2, doc 07 §22).
#
# When a message arrives from an external source (queue, webhook, etc.) that can be delivered
# more than once, the consumer records it here with its source and external ID. On subsequent
# receipt of the same message, the consumer detects a duplicate and skips reprocessing.
#
# This prevents duplicate logical effects: e.g., receiving the same deployment notification
# twice should not create two operations.
#
class InboxEvent < ApplicationRecord
  include UlidPrimaryKey

  # Validations.
  validates :source, presence: true
  validates :source_event_id, presence: true

  scope :processed, -> { where("processed_at IS NOT NULL") }
  scope :pending, -> { where(processed_at: nil) }
  scope :by_source, ->(source) { where(source: source) }

  # Mark this event as processed.
  def mark_processed!(result_ref = nil)
    update!(processed_at: Time.current.utc, result_ref: result_ref)
  end

  # Check if this event has been processed already.
  def processed?
    processed_at.present?
  end
end
