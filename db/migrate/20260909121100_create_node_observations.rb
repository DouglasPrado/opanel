# migration-phase: expand
#
# The NodeObservation — the actual state of a Docker Swarm node (doc 09 §10).
#
# ## Immutable and timestamped
#
# Observations are facts: what the Control Plane saw when it looked at the runtime.
# Each observation is appended, never edited. The Node table denormalizes `last_seen_at`
# for UI efficiency, but the authoritative reading timestamp lives here.
#
# ## Actual state separate from desired state
#
# `status`, `availability`, and `resources` here are **observed** from the Swarm.
# The corresponding columns on `Node` (if they exist as desired state, handled by
# a future Story) are what the operator intends. This table records reality.
#
# ## Retention is shorter than Desired State
#
# doc 09 §25: observations are reconstruable and can have shorter retention than
# critical state. A cleanup job may GC old observations after a window, but Node
# itself persists longer.
class CreateNodeObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :node_observations, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :node_id, :"char(26)", null: false

      # The status the node reported at observation time. Copied from Node#status
      # for denormalization after insertion, but the source of truth for this
      # observation lives here, immutable.
      t.text :status, null: false

      # The availability the node reported (or was set to). In normal operation,
      # matches the Node#availability on the parent unless a mismatch is being
      # corrected in a future Story.
      t.text :availability

      # The resources (CPU, memory) the node reported. Observed from Swarm.
      # Stored as JSONB for extensibility; schema TBD in a later Story
      # (M09-02, host metrics).
      t.jsonb :resources

      # The Docker Engine version the node reported.
      t.text :engine_version

      # When this observation was taken. The source of truth for staleness
      # (doc 10 §25). A Node can be READY or DEGRADED, but if this timestamp
      # is old, the UI must say "last observed X seconds ago" rather than
      # presenting it as current.
      t.timestamptz :observed_at, null: false

      t.timestamptz :created_at, null: false
    end

    add_foreign_key :node_observations, :nodes, column: :node_id, on_delete: :cascade

    # For efficiently finding the latest observation of a node.
    # A cleanup/archival job can delete old observations; this index helps find
    # what to keep.
    #
    # migration-index-review: new empty table.
    add_index :node_observations, %i[node_id observed_at], order: { observed_at: :desc },
      name: "index_node_observations_latest_per_node"

    # CHECK constraints.
    add_check_constraint :node_observations,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "node_observations_id_is_ulid"

    add_check_constraint :node_observations,
      "node_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "node_observations_node_id_is_ulid"

    # status must match the doc 17 state machine.
    add_check_constraint :node_observations,
      "status IN ('JOINING', 'READY', 'DEGRADED', 'DOWN', 'REMOVING')",
      name: "node_observations_status_is_known"

    # availability when observed (optional, can be null if the observation
    # doesn't include it).
    add_check_constraint :node_observations,
      "availability IS NULL OR availability IN ('ACTIVE', 'PAUSE', 'DRAIN')",
      name: "node_observations_availability_is_valid"
  end
end
