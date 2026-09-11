class CreateResourceLocks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Resource locks serialize mutations on the same entity (M01-15 §14.1).
    # One lock per scope (serviceId, nodeId, etc.), with a TTL and fencing token
    # to prevent stale workers from applying obsolete results.
    #
    # Acquisition is a single atomic statement (C1):
    #   INSERT ... ON CONFLICT (scope_key) DO UPDATE SET ... WHERE lease_until <= NOW()
    # Zero rows returned means the lock is held. Fencing token is incremented by the
    # database under row lock, guaranteeing monotonicity (AC3).
    create_table :resource_locks, id: :string, primary_key: :id do |t|
      # Scoping: the lock belongs to a Team (C4, AC10: owner is not client-provided).
      t.string :team_id, null: false, index: true

      # Scope key: identifies what is locked (serviceId, nodeId, clusterId, etc.).
      # One row per scope, for the life of the scope. Unique constraint enforces it (C1).
      t.text :scope_key, null: false

      # Owner: worker identity that holds the lease. Derived from the process,
      # never accepted from a caller (AC10). Set at acquisition; renewed; cleared at release.
      t.string :owner, null: false

      # Lease until: when this lock expires. If now() >= lease_until, another worker
      # may acquire (C1). Monotonicity and takeover enforced by ON CONFLICT ... WHERE.
      t.datetime :lease_until, precision: 6, null: false

      # Fencing token: monotonic per scope, incremented on each acquisition.
      # A worker returning after lease expiry presents an old token; fenced write refuses it (AC4).
      # Starts at 0 for each new scope, incremented by the database under lock.
      t.bigint :fencing_token, null: false, default: 0

      # Audit and correlation.
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false

      # Unique constraint: one row per scope, for the life of the scope.
      # migration-index-review: new table, indexes built during table creation.
      t.index :scope_key, unique: true, name: "index_resource_locks_scope_key_unique"
    end

    # Foreign key to teams (tenancy boundary).
    add_foreign_key :resource_locks, :teams, column: :team_id, primary_key: :id, on_delete: :restrict

    # ULID id constraint.
    add_check_constraint :resource_locks,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "resource_locks_id_is_ulid"

    # Scope key must not be empty.
    add_check_constraint :resource_locks,
      "btrim(scope_key) <> ''",
      name: "resource_locks_scope_key_present"

    # Owner must not be empty.
    add_check_constraint :resource_locks,
      "btrim(owner) <> ''",
      name: "resource_locks_owner_present"

    # Fencing token must be non-negative.
    add_check_constraint :resource_locks,
      "fencing_token >= 0",
      name: "resource_locks_fencing_token_non_negative"

    # Team id constraint.
    add_check_constraint :resource_locks,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "resource_locks_team_id_is_ulid"
  end
end
