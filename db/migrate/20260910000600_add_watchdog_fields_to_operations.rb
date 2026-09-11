class AddWatchdogFieldsToOperations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Watchdog marks an Operation as STALLED after a threshold (Annex B §6, doc 07 §22).
    # This is an observation/attribute, not a status change (doc 07 §5.2 has no STALLED status).
    # An Operation with stalled_at != nil is observed to have no progress.
    add_column :operations, :stalled_at, :datetime, precision: 6
    add_column :operations, :stalled_reason, :string

    # Index to find stalled operations quickly for alerting and observability.
    # migration-index-review: existing table with stable schema, stalled_at is optional and sparse.
    add_index :operations, :stalled_at, name: "index_operations_stalled",
      algorithm: :concurrently
  end
end
