class CreateInboxEvents < ActiveRecord::Migration[8.1]
  def change
    # Inbox events for deduplication of external messages (doc 07 §10.2, §22).
    # When a message arrives from a queue or webhook, the consumer records it here
    # with source + source_event_id (the externalId from doc 07) to detect and skip duplicates.
    # This prevents duplicate logical effects when the same message is delivered twice.
    create_table :inbox_events, id: :string, primary_key: :id do |t|
      # Source of the message: "queue_publisher", "github_webhook", etc.
      t.string :source, null: false, index: true

      # External message ID from the source: idempotency key or webhook delivery ID.
      # Combined with source to form the dedup key.
      # Named source_event_id (not external_id) to avoid shadowing UlidPrimaryKey.external_id method.
      t.string :source_event_id, null: false, index: true

      # When the message was first processed (UTC). Persisted so we know
      # a duplicate message has been seen before.
      t.datetime :processed_at, precision: 6

      # Optional reference to the Operation or other result (for audit/tracing).
      t.string :result_ref

      # Audit.
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false

      # Unique constraint: (source, source_event_id) pair determines dedup scope.
      # migration-index-review: new table, indexes built during table creation.
      t.index %i[source source_event_id],
        unique: true,
        name: "index_inbox_events_source_event_id_unique"
    end
  end
end
