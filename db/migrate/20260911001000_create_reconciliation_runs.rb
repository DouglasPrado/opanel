class CreateReconciliationRuns < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :reconciliation_runs, id: :string, primary_key: :id do |t|
      # Scoping: identifies which resource was reconciled.
      t.string :resource_type, null: false, index: true
      t.string :resource_id, null: false, index: true
      t.string :team_id, null: false, index: true  # denormalized for tenancy

      # Trigger: what caused this reconcile (OPERATION, PERIODIC, MANUAL) — for observability.
      t.string :trigger, null: false

      # Diff class (doc 07 §11.4): NOOP, CREATE, UPDATE_SAFE, ROLLOUT, DELETE, BLOCKED, DRIFT.
      t.string :diff_class, null: false

      # Actions applied as JSON array, for auditability without reproducing (AC10).
      t.jsonb :actions_applied, null: false, default: []

      # Result: SUCCESS, BLOCKED, FAILED (AC10).
      t.string :result, null: false

      # Error reason if result != SUCCESS (for diagnosis without logs).
      t.text :error_reason

      # Timeline: observation timestamp, reconcile duration (for diagnosis).
      t.datetime :observed_at, precision: 6
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
    end

    # Indexes for observability and cleanup.
    # migration-index-review: new table, empty on creation, safe to build concurrently
    add_index :reconciliation_runs,
      %i[resource_type resource_id created_at],
      name: "index_reconciliation_runs_on_resource_and_created",
      order: { created_at: :desc },
      algorithm: :concurrently

    # migration-index-review: new table, empty on creation, safe to build concurrently
    add_index :reconciliation_runs,
      %i[team_id created_at],
      name: "index_reconciliation_runs_on_team_and_created",
      order: { created_at: :desc },
      algorithm: :concurrently

    # Integrity constraints.
    results = %w[SUCCESS BLOCKED FAILED].join("', '")
    add_check_constraint :reconciliation_runs,
      "result IN ('#{results}')",
      name: "reconciliation_runs_result_is_known"

    diff_classes = %w[NOOP CREATE UPDATE_SAFE ROLLOUT DELETE BLOCKED DRIFT].join("', '")
    add_check_constraint :reconciliation_runs,
      "diff_class IN ('#{diff_classes}')",
      name: "reconciliation_runs_diff_class_is_known"

    triggers = %w[OPERATION PERIODIC MANUAL].join("', '")
    add_check_constraint :reconciliation_runs,
      "trigger IN ('#{triggers}')",
      name: "reconciliation_runs_trigger_is_known"

    add_check_constraint :reconciliation_runs,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "reconciliation_runs_id_is_ulid"

    add_check_constraint :reconciliation_runs,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "reconciliation_runs_team_id_is_ulid"

    add_check_constraint :reconciliation_runs,
      "result = 'SUCCESS' OR error_reason IS NOT NULL",
      name: "reconciliation_runs_failed_requires_reason"

    # Foreign key (tenancy).
    add_foreign_key :reconciliation_runs, :teams, column: :team_id, primary_key: :id, on_delete: :restrict
  end
end
