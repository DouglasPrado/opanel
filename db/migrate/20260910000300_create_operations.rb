class CreateOperations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :operations, id: :string, primary_key: :id do |t|
      # Scoping: the Operation belongs to a Team and references a specific resource.
      t.string :team_id, null: false, index: true
      t.string :resource_type, null: false, index: true
      t.string :resource_id, null: false, index: true

      # Operation type: DEPLOY, SCALE, UPDATE_SERVICE, etc. (doc 07 §5.1).
      t.string :type, null: false, index: true

      # State machine (doc 07 §5.2): PENDING → QUEUED → RUNNING → (WAITING_RUNTIME → VERIFYING) → SUCCEEDED | RETRYABLE → QUEUED, or terminal states.
      t.string :status, null: false, index: true

      # Desired revision of the resource this Operation applies.
      t.bigint :desired_revision, null: false

      # Idempotency: the same Team + endpoint semantic + key produces one logical operation (doc 07 §6.1).
      # Constraint enforced in migration comment below.
      t.string :idempotency_key

      # Lease and fencing: worker claims to execute (M01-15 Locks, leases and fencing).
      # Fields born here; mechanism in M01-15.
      t.string :lease_owner
      t.datetime :lease_until, precision: 6
      t.bigint :fencing_token

      # Retry tracking (doc 07 §5.1, doc 09 §5.1).
      t.integer :attempt_count, null: false, default: 0

      # Payload: JSONB sanitized and versioned (doc 09 §5.1, no secrets).
      t.jsonb :payload, null: false, default: {}

      # Error code: stable, not a stack trace (doc 07 §5.3, doc 09 §28).
      # Must be one of: Validation, Conflict, Transient, Runtime rejection, Timeout, Unknown outcome (doc 07 §5.3).
      t.string :error_code

      # Audit and correlation.
      t.string :request_id
      t.string :correlation_id
      t.string :requested_by

      # Timeline (doc 07 §17.2).
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
      t.datetime :started_at, precision: 6
      t.datetime :finished_at, precision: 6

      # Add next_attempt_at for retry scheduling (M01-14 dispatcher, doc 07 §10).
      t.datetime :next_attempt_at, precision: 6

      # Indexes for scheduler and reconciler (doc 09 §18).
      # INDEX(resourceType, status, nextAttemptAt) for dispatcher and reconciler queries.
      t.index %i[resource_type status next_attempt_at],
        name: "index_operations_for_retry_dispatch",
        algorithm: :concurrently
    end

    # Idempotency scope: the pair Team + endpoint semantic + key (doc 07 §6.1).
    # The "endpoint semantic" is the operation type on a specific resource.
    # Partial unique: key must be provided (IS NOT NULL) to be enforced (doc 09 §18).
    # Cite doc 07 §6.1 in the constraint name.
    # migration-index-review: new table, safe to build without concurrency
    add_index :operations,
      %i[team_id resource_type resource_id type idempotency_key],
      name: "index_operations_idempotency_doc_07_6_1",
      unique: true,
      where: "idempotency_key IS NOT NULL"

    # Integrity constraints per AGENT_RULES and doc 07 §5.2.
    statuses = %w[PENDING QUEUED RUNNING WAITING_RUNTIME VERIFYING SUCCEEDED RETRYABLE
                  FAILED CANCELED SUPERSEDED TIMED_OUT].join("', '")
    add_check_constraint :operations,
      "status IN ('#{statuses}')",
      name: "status_in_valid_set"

    add_check_constraint :operations,
      "attempt_count >= 0",
      name: "attempt_count_non_negative"

    add_check_constraint :operations,
      "(lease_owner IS NULL AND lease_until IS NULL) OR " \
      "(lease_owner IS NOT NULL AND lease_until IS NOT NULL)",
      name: "lease_pair_coherent"

    add_check_constraint :operations,
      "payload ? 'schemaVersion'",
      name: "payload_has_schema_version"

    # Foreign key to teams (tenancy boundary).
    add_foreign_key :operations, :teams, column: :team_id, primary_key: :id, on_delete: :restrict
  end
end
