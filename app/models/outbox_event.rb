# An OutboxEvent records domain facts durably in the same transaction as intent (doc 07 §10, doc 09 §9.3).
#
# OutboxEvent provides the Transactional Outbox pattern: changes to Desired State,
# Operations, and domain events are committed together in PostgreSQL. After commit,
# a dispatcher (M01-14) publishes unpublished events to the queue.
#
# This separation eliminates the window where "the change was saved but the work
# was not queued". If the process crashes between commit and publish, the event
# survives in PostgreSQL with published_at = NULL, and the periodic sweep recovers it.
#
class OutboxEvent < ApplicationRecord
  include UlidPrimaryKey

  validates :aggregate_type, presence: true
  validates :aggregate_id, presence: true
  validates :event_type, presence: true
  validates :schema_version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :payload, presence: true
  validates :occurred_at, presence: true

  scope :unpublished, -> { where(published_at: nil) }
  scope :published, -> { where.not(published_at: nil) }
  scope :ordered, -> { order(:occurred_at, :created_at) }

  # Mark this event as published to the queue.
  def mark_published!
    update!(published_at: Time.current.utc)
  end
end
