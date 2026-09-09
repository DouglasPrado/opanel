# migration-phase: expand
#
# The append-only record of privileged actions (doc 04 §10, doc 09 §15.1).
#
# ## Append-only is enforced, not merely intended
#
# "The application does not update it" is a property of code somebody can change
# without noticing. So the table also carries a rule PostgreSQL enforces: a
# trigger would be the obvious choice and is exactly what SC-17 and M01-02 ruled
# out — the Ruby schema dumper emits no triggers, so the guarantee would exist in
# a migrated database and vanish from every database created by db:schema:load,
# including the test one.
#
# What survives the dump is a CHECK, and a CHECK can express immutability if the
# row carries something an UPDATE must change. `created_at` cannot be that (an
# UPDATE may leave it alone), so the enforcement here is the pair:
#
#   * `revision` is `CHECK (revision = 1)` — any UPDATE that touches it fails, and
#     the column exists for no other reason;
#   * the model refuses `update` and `destroy`, and a spec asserts both the code
#     path and the database.
#
# That is honest about what it is: the database blocks the *shape* of a rewrite,
# and the Story's "sem UPDATE nem DELETE pela aplicação, verificada por teste" is
# what covers the rest. A DBA with table privileges can still delete rows — no
# in-database rule can prevent that, and pretending otherwise would be worse than
# saying so.
class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true

      # Nullable **only** for installation events (doc 09 §15.1). A CHECK cannot
      # tell which events those are — that is domain knowledge — so the model and
      # a spec carry it, and the column stays nullable so an instance event can be
      # recorded at all.
      t.column :team_id, :"char(26)"

      t.text :actor_type, null: false
      t.column :actor_id, :"char(26)"
      t.text :action, null: false
      t.text :resource_type, null: false
      t.column :resource_id, :"char(26)"
      t.column :environment_id, :"char(26)"

      t.text :request_id, null: false
      t.text :correlation_id, null: false
      t.column :operation_id, :"char(26)"

      t.inet :ip
      t.text :user_agent

      # Sanitised by allowlist before they get here. `{}` rather than NULL so a
      # reader never has to distinguish "no change" from "not recorded".
      t.jsonb :before, null: false, default: {}
      t.jsonb :after, null: false, default: {}

      t.text :result, null: false

      # See the class comment: the column exists to make immutability expressible
      # as a CHECK that survives `db/schema.rb`.
      t.integer :revision, null: false, default: 1

      t.timestamptz :created_at, null: false
    end

    add_check_constraint :audit_logs, "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "audit_logs_id_is_ulid"
    add_check_constraint :audit_logs,
      "actor_type IN ('USER', 'API_TOKEN', 'SYSTEM', 'RECOVERY')",
      name: "audit_logs_actor_type_is_known"
    add_check_constraint :audit_logs, "result IN ('SUCCESS', 'DENIED', 'FAILED')",
      name: "audit_logs_result_is_known"
    # A stable, namespaced action name (doc 09 §15.1): `team.created`,
    # `installation.bootstrapped`. Enforced so a free-text action cannot enter and
    # make the trail unqueryable.
    add_check_constraint :audit_logs, "action ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$'",
      name: "audit_logs_action_is_namespaced"
    add_check_constraint :audit_logs, "revision = 1",
      name: "audit_logs_are_append_only"
    add_check_constraint :audit_logs, "btrim(request_id) <> ''",
      name: "audit_logs_request_id_present"
    add_check_constraint :audit_logs, "btrim(correlation_id) <> ''",
      name: "audit_logs_correlation_id_present"

    # Deliberately no foreign keys. An audit record outlives what it describes:
    # a Team deleted in M11 must not take the record of who deleted it, and
    # `ON DELETE RESTRICT` would make deletion impossible while `CASCADE` would
    # erase the trail. The ids are recorded as facts, not as references.

    # doc 09 §18, both indexes named there.
    # migration-index-review: new empty table — the builds are instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :audit_logs, [ :team_id, :created_at ], order: { created_at: :desc },
      name: "index_audit_logs_on_team_id_and_created_at"
    add_index :audit_logs, [ :resource_type, :resource_id, :created_at ],
      order: { created_at: :desc },
      name: "index_audit_logs_on_resource_and_created_at"
    # The chain the Story's AC8 asks for: from one request id to everything that
    # happened under it.
    add_index :audit_logs, :request_id, name: "index_audit_logs_on_request_id"
  end
end
