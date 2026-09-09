# migration-phase: expand
#
# Instance roles administer the *installation*, not a tenant (doc 09 §3.3). They
# are a separate table from `team_members` for the reason doc 04 §7.1 gives: a
# Team OWNER need not operate the cluster, and an instance administrator need not
# own any Team. Keeping them apart is what makes "transferring TEAM_OWNER does not
# transfer INSTANCE_ADMIN" (doc 04 §7.1, AC4) true by construction rather than by
# remembering to write it.
#
# Two constraints carry the Story's security requirements into PostgreSQL:
#
#   1. `index_instance_roles_one_active_grant_per_user_and_role` — a user holds a
#      given role once. Re-granting an active role is refused rather than
#      producing two rows that must later be revoked one by one.
#
#   2. `index_instance_roles_single_bootstrap` — a unique index over a constant
#      expression, restricted to the bootstrap grant. Because the expression is
#      the same value for every row, the index admits **one row in the whole
#      table**, which is exactly AC2: "duas requisições simultâneas de primeiro
#      cadastro produzem um bootstrap". The second transaction to reach COMMIT
#      loses on the index rather than on a check that read stale state, so no
#      lock, no advisory lock and no SERIALIZABLE isolation is required.
#
# AC5 — "revoking the last active INSTANCE_ADMIN is blocked" — is deliberately
# *not* here. It is a condition over the set of remaining rows, which no unique
# index expresses; `RevokeInstanceRole` enforces it under an explicit lock, and
# the Story asks for a stable error rather than for the database to refuse.
class CreateInstanceRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :instance_roles, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :user_id, :"char(26)", null: false
      t.text :role, null: false
      # Marks the grant the installation bootstrap made. Nullable rather than
      # boolean: `NULL` does not participate in a partial unique index, so every
      # ordinary grant is invisible to the singleton index while the one
      # bootstrap row occupies it.
      t.boolean :granted_by_bootstrap
      t.timestamptz :revoked_at
      t.timestamps null: false
    end

    add_check_constraint :instance_roles, "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "instance_roles_id_is_ulid"
    add_check_constraint :instance_roles, "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "instance_roles_user_id_is_ulid"
    add_check_constraint :instance_roles,
      "role IN ('INSTANCE_ADMIN', 'INSTANCE_OPERATOR', 'INSTANCE_AUDITOR')",
      name: "instance_roles_role_is_known"
    # `granted_by_bootstrap` is either the marker or absent; `false` would be a
    # third meaning for what is a two-state fact, and it would also collide in the
    # singleton index below.
    add_check_constraint :instance_roles, "granted_by_bootstrap IS NULL OR granted_by_bootstrap",
      name: "instance_roles_bootstrap_marker_is_true_or_absent"
    # Only the bootstrap grant may be INSTANCE_ADMIN-by-bootstrap; marking any
    # other role would let a lesser grant occupy the singleton slot and block the
    # real bootstrap.
    add_check_constraint :instance_roles,
      "granted_by_bootstrap IS NULL OR role = 'INSTANCE_ADMIN'",
      name: "instance_roles_bootstrap_is_admin"

    add_foreign_key :instance_roles, :users, column: :user_id, on_delete: :restrict

    # migration-index-review: new empty table — the builds are instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :instance_roles, [ :user_id, :role ], unique: true,
      where: "revoked_at IS NULL",
      name: "index_instance_roles_one_active_grant_per_user_and_role"

    # AC2, in the database. See the class comment: a unique index over a constant
    # expression admits one row overall. Declared through `add_index` rather than
    # `execute` so the migration stays reversible — `bin/migration-gate` refuses an
    # `execute` inside `change`, and it is right to: a rollout that cannot roll
    # back is a decision, not an implementation detail.
    add_index :instance_roles, "(granted_by_bootstrap)", unique: true,
      where: "granted_by_bootstrap",
      name: "index_instance_roles_single_bootstrap"

    # The read behind `InstallationBootstrapState` and behind every authorization
    # check that asks "is this actor an instance administrator".
    add_index :instance_roles, [ :role ], where: "revoked_at IS NULL",
      name: "index_instance_roles_active_by_role"
  end
end
