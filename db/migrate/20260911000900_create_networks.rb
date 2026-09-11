class CreateNetworks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :networks, id: :string, primary_key: :id do |t|
      # Scoping: belongs to an Environment and a Cluster.
      t.string :environment_id, null: false, index: true
      t.string :cluster_id, null: false, index: true
      t.string :team_id, null: false, index: true  # denormalized for tenancy

      # Swarm resource identity: filled in after creation.
      t.string :swarm_network_id

      # Deterministic name derived from IDs (doc 08 §5, Opanel::Ownership).
      t.text :name, null: false

      # Driver: overlay is the only driver for application networks (doc 08 §4.1).
      t.string :driver, null: false, default: "overlay"

      # Encryption intent (doc 08 §4.1): recorded but may not be enabled without AC.
      t.boolean :encrypted, null: false, default: false

      # Status: PROVISIONING, READY, DEGRADED, DELETING (doc 09 §5.2, doc 07 §17.1).
      t.string :status, null: false, default: "PROVISIONING", index: true

      # Revision tracking (doc 07 §4, §11.3): applied advances only after re-inspection.
      t.bigint :desired_revision, null: false, default: 1
      t.bigint :applied_revision

      # Timeline.
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
      t.datetime :deleted_at
    end

    # migration-index-review: new table, empty on creation, safe to build concurrently
    # Unique network per environment (one network per environment).
    add_index :networks,
      :environment_id,
      name: "index_networks_unique_per_environment",
      unique: true,
      where: "deleted_at IS NULL"

    # migration-index-review: new table, empty on creation, safe to build concurrently
    # Indexes for queries (tenancy and observability).
    # migration-index-review: new table, empty on creation, safe to build concurrently
    add_index :networks,
      %i[team_id status],
      name: "index_networks_on_team_id_and_status",
      algorithm: :concurrently

    # migration-index-review: new table, empty on creation, safe to build concurrently
    add_index :networks,
      %i[cluster_id status],
      name: "index_networks_on_cluster_id_and_status",
      algorithm: :concurrently

    # Integrity constraints (AGENT_RULES, doc 07).
    statuses = %w[PROVISIONING READY DEGRADED DELETING].join("', '")
    add_check_constraint :networks,
      "status IN ('#{statuses}')",
      name: "networks_status_is_known"

    add_check_constraint :networks,
      "applied_revision IS NULL OR applied_revision <= desired_revision",
      name: "networks_applied_revision_not_ahead"

    add_check_constraint :networks,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "networks_id_is_ulid"

    add_check_constraint :networks,
      "environment_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "networks_environment_id_is_ulid"

    add_check_constraint :networks,
      "cluster_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "networks_cluster_id_is_ulid"

    add_check_constraint :networks,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "networks_team_id_is_ulid"

    add_check_constraint :networks,
      "btrim(name) <> ''",
      name: "networks_name_present"

    add_check_constraint :networks,
      "swarm_network_id IS NULL OR swarm_network_id ~ '^[a-z0-9]+$'",
      name: "networks_swarm_network_id_valid"

    # Foreign keys (denormalization for performance, but FK for integrity).
    add_foreign_key :networks, :environments, column: :environment_id, primary_key: :id, on_delete: :restrict
    add_foreign_key :networks, :clusters, column: :cluster_id, primary_key: :id, on_delete: :restrict
    add_foreign_key :networks, :teams, column: :team_id, primary_key: :id, on_delete: :restrict
  end
end
