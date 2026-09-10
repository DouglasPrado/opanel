class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events, id: :string, primary_key: :id do |t|
      # The aggregate that originated this event (doc 09 §9.3).
      t.string :aggregate_type, null: false, index: true
      t.string :aggregate_id, null: false, index: true

      # Event type: stable, domain-oriented, versionable (doc 09 §9.3, doc 07 §20.2).
      t.string :event_type, null: false
      t.integer :schema_version, null: false, default: 1

      # Payload: no secrets (doc 09 §9.3, doc 07 §21).
      t.jsonb :payload, null: false, default: {}

      # Partition key: for ordering when necessary (doc 09 §9.3).
      t.string :partition_key

      # Timeline: when the event occurred logically (commit time) vs when it was published.
      # occurred_at is the business time; published_at is null until dispatcher publishes.
      # (doc 07 §10, Transactional Outbox).
      t.datetime :occurred_at, precision: 6, null: false
      t.datetime :published_at, precision: 6

      # Audit.
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false

      # Indexes for dispatcher and reconciler (doc 09 §18).
      # INDEX(publishedAt, occurredAt) for the dispatcher (M01-14).
      t.index %i[published_at occurred_at], name: "index_outbox_events_for_publisher"

      # Index for finding unpublished events (M01-14 dispatcher needs this).
      t.index :published_at, name: "index_outbox_events_unpublished", where: "published_at IS NULL"
    end

    # Integrity constraint: schema_version must be positive (doc 09 §9.3).
    add_check_constraint :outbox_events,
      "schema_version > 0",
      name: "schema_version_positive"
  end
end
