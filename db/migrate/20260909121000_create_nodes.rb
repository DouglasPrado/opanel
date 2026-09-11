# migration-phase: expand
#
# The Node — a Docker Swarm node as a product resource (doc 09 §4.2).
#
# ## Desired state and actual state are separate
#
# doc 09 §10 forbids sharing columns between desired state (what the operator
# configured) and actual state (what the runtime reports). `swarm_node_id`, `role`,
# `availability` and addresses are **desired** configuration of the node in the
# Cluster. The **actual** observation lives in `NodeObservation`, which is
# immutable, timestamped, and reconstruable after a Control Plane restart.
#
# ## `last_seen_at` as a denormalization
#
# `last_seen_at` on the Node is the timestamp of the most recent observation,
# denormalized here for convenience in the UI. The authoritative observation
# timestamp lives in NodeObservation#observed_at, never here. A node with no
# observation yet has `last_seen_at = NULL`.
#
# ## `swarm_node_id` is UNIQUE per cluster
#
# doc 09 §4.2. A node cannot register twice in the same cluster. The uniqueness
# is partial: a `swarm_node_id` from one Swarm can match one from another (if
# the operator rebuilds the Swarm), but within a cluster boundary the id identifies
# a single Node row.
class CreateNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :nodes, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :cluster_id, :"char(26)", null: false

      # The id the Docker Swarm assigned to this node; observed, never chosen.
      t.text :swarm_node_id, null: false

      # Observed from the Swarm at join time.
      t.text :hostname, null: false

      # The role this node was given. MANAGER or WORKER (doc 09 §4.2).
      t.text :role, null: false

      # Additional capabilities not expressed by role (doc 09 §4.2: INGRESS, BUILDER
      # and labels). Stored as JSONB because constraints on capabilities are rare.
      t.jsonb :capabilities, default: {}, null: false

      # The availability this operator set for the node. Controls whether the node
      # accepts new Tasks. ACTIVE, PAUSE or DRAIN (doc 09 §4.2). Not observed
      # directly from the Swarm, but set by operators and observed back.
      t.text :availability, null: false, default: "ACTIVE"

      # The last status this node was **observed** in. The observation carries the
      # timestamp, and this column denormalizes the latest status for efficient
      # queries. Kept in sync with the most recent NodeObservation#status by the
      # job that creates observations.
      t.text :status, null: false, default: "JOINING"

      # The addresses the node was observed with. These are copies of what Swarm
      # reported; the authoritative observation lives in NodeObservation.
      # The advertise address is the one other nodes use to reach this one.
      t.text :advertise_address
      # Private and public addresses are optional (doc 06 §5.2).
      t.text :private_address
      t.text :public_address

      # Labels the operator may have set on the node, or observed from the Swarm.
      # Stored as JSONB for extensibility.
      t.jsonb :labels, default: {}, null: false

      # When the node was last observed by the Control Plane. Denormalized from
      # NodeObservation#observed_at for quick staleness checks in the UI. NULL if
      # the node has never been observed.
      t.timestamptz :last_seen_at

      t.timestamptz :deleted_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    add_foreign_key :nodes, :clusters, column: :cluster_id, on_delete: :restrict

    # UNIQUE per cluster (doc 09 §4.2). The swarm_node_id is the runtime's
    # identifier; no two Nodes in the same Cluster can claim the same swarm_node_id.
    # A swarm_node_id can repeat across different clusters if the Swarms are
    # independent or the daemon was rebuilt.
    #
    # migration-index-review: new empty table.
    add_index :nodes, %i[cluster_id swarm_node_id], unique: true,
      name: "index_nodes_unique_swarm_node_id_per_cluster"

    # For efficient status queries per cluster.
    add_index :nodes, %i[cluster_id status], name: "index_nodes_on_cluster_id_and_status"

    # For listing nodes of a cluster in order.
    add_index :nodes, %i[cluster_id id], name: "index_nodes_on_cluster_id_and_id"

    # CHECK constraints for state invariants (doc 09 §4.2).
    add_check_constraint :nodes,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "nodes_id_is_ulid"

    add_check_constraint :nodes,
      "cluster_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "nodes_cluster_id_is_ulid"

    add_check_constraint :nodes,
      "btrim(swarm_node_id) <> ''",
      name: "nodes_swarm_node_id_present"

    add_check_constraint :nodes,
      "btrim(hostname) <> ''",
      name: "nodes_hostname_present"

    add_check_constraint :nodes,
      "role IN ('MANAGER', 'WORKER')",
      name: "nodes_role_is_known"

    # availability per doc 09 §4.2.
    add_check_constraint :nodes,
      "availability IN ('ACTIVE', 'PAUSE', 'DRAIN')",
      name: "nodes_availability_is_known"

    # status per doc 09 §4.2 and doc 17 (the state machine).
    add_check_constraint :nodes,
      "status IN ('JOINING', 'READY', 'DEGRADED', 'DOWN', 'REMOVING')",
      name: "nodes_status_is_known"
  end
end
