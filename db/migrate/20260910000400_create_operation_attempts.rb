class CreateOperationAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :operation_attempts, id: :string, primary_key: :id do |t|
      # Each attempt is immutable: a new record, never overwritten (doc 09 §9.2).
      t.string :operation_id, null: false, index: true
      t.integer :attempt_number, null: false

      # Executor that claimed this operation.
      t.string :executor_id

      # Timeline: each attempt preserves start and end (doc 09 §9.2, doc 07 §17.2).
      t.datetime :started_at, precision: 6, null: false
      t.datetime :finished_at, precision: 6

      # Outcome and error categorization (doc 07 §5.3).
      t.string :outcome  # APPLIED, NOOP, CONFLICT, RETRYABLE, FAILED, etc.
      t.string :error_code
      t.text :error_message

      # Telemetry and metadata safe for logging (doc 07 §21, doc 09 §9.2).
      t.jsonb :metadata, default: {}

      # Audit.
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false

      t.index %i[operation_id attempt_number], unique: true
    end

    # Integrity constraint: attempt_number must be >= 1 (doc 09 §9.2).
    add_check_constraint :operation_attempts,
      "attempt_number >= 1",
      name: "attempt_number_positive"

    add_foreign_key :operation_attempts, :operations, column: :operation_id, primary_key: :id
  end
end
