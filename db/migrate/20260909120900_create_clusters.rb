# migration-phase: expand
#
# The Cluster — a Docker Swarm as a product resource (doc 09 §4.1).
#
# ## `team_id` is NOT NULL, and that is a decision, not an omission
#
# doc 09 §4.1 says the column is *"nullable apenas para cluster de sistema
# explicitamente modelado"*. `SC-12` resolved that restrictively for this whole
# pack: a nullable owner is an authorization path with no tenancy boundary, which
# Annex C §7.3 forbids outright. A system cluster is not modelled here, and
# modelling one later needs its own ADR and an explicit instance Policy — not a
# nullable column somebody notices afterwards.
#
# ## What the columns are for
#
# `swarm_id` is **observed**, not chosen: it is whatever the Engine reports after
# `swarm init` or after adopting an existing Swarm. Unique when known, so two
# Cluster rows cannot claim the same Swarm — which is how a duplicated bootstrap
# would otherwise produce two records converging on one runtime.
#
# `observed_at` is what makes AC11 true. The status column holds the **last
# observation**, and the timestamp says when it was taken. Nothing here is a
# stored boolean about health: a reader that cannot see the age of a reading
# cannot tell "healthy" from "was healthy an hour ago".
class CreateClusters < ActiveRecord::Migration[8.1]
  def change
    create_table :clusters, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :team_id, :"char(26)", null: false
      t.text :name, null: false
      t.text :slug, null: false
      t.text :status, null: false, default: "PROVISIONING"

      # Observed from the Engine. Absent until the Swarm exists.
      t.text :swarm_id
      # The advertise address the Swarm was initialised with, kept because
      # diagnosing a partition starts with "which address did we tell the other
      # nodes to reach us on".
      t.text :advertise_address

      # doc 09 §4.1. `applied_revision` is null until a reconciler has converged
      # this Cluster at least once, which is `M01-18`.
      t.bigint :desired_revision, null: false, default: 1
      t.bigint :applied_revision

      # When the status was last read from the runtime. See the note above.
      t.timestamptz :observed_at
      # Why the Cluster is not READY, classified. The Story's Observability
      # Requirements are explicit that a daemon failure must arrive as a named
      # cause and never as a generic timeout.
      t.text :unreachable_reason

      t.timestamptz :deleted_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # RESTRICT, like every other tenant-owned table here: doc 09 §25 makes removal
    # a lifecycle, and a Team deleted out from under its Clusters would orphan a
    # running Swarm that nothing then reconciles.
    add_foreign_key :clusters, :teams, column: :team_id, on_delete: :restrict

    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :clusters, %i[team_id slug], unique: true, where: "deleted_at IS NULL",
      name: "index_clusters_unique_slug_per_team_when_not_deleted"

    # doc 09 §18's "UNIQUE quando conhecido", literally: partial on the rows that
    # know their Swarm. Two Clusters pointing at one Swarm is a split brain in the
    # control plane, not a data-entry mistake.
    #
    # migration-index-review: new empty table.
    add_index :clusters, :swarm_id, unique: true, where: "swarm_id IS NOT NULL",
      name: "index_clusters_unique_swarm_id_when_known"

    add_index :clusters, %i[team_id id], name: "index_clusters_on_team_id_and_id"

    add_check_constraint :clusters,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "clusters_id_is_ulid"

    add_check_constraint :clusters,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "clusters_team_id_is_ulid"

    add_check_constraint :clusters,
      "btrim(name) <> '' AND length(name) <= 120",
      name: "clusters_name_present"

    add_check_constraint :clusters,
      "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' AND length(slug) BETWEEN 2 AND 63",
      name: "clusters_slug_format"

    # doc 09 §4.1, the six states verbatim. `text` + CHECK rather than an ENUM so
    # a seventh state is an ordinary expand migration.
    add_check_constraint :clusters,
      "status IN ('PROVISIONING', 'READY', 'DEGRADED', 'MAINTENANCE', 'UNREACHABLE', 'DELETING')",
      name: "clusters_status_is_known"

    # A status that is not PROVISIONING is an observation, and an observation
    # without its timestamp is a claim. This is AC11 held by the database rather
    # than by every writer remembering.
    add_check_constraint :clusters,
      "status = 'PROVISIONING' OR observed_at IS NOT NULL",
      name: "clusters_observed_status_has_a_timestamp"

    # A Swarm id the Engine did not produce is a typo. The format is Docker's, not
    # ours: 25 lowercase base36 characters.
    add_check_constraint :clusters,
      "swarm_id IS NULL OR swarm_id ~ '^[a-z0-9]{20,32}$'",
      name: "clusters_swarm_id_shape"

    add_check_constraint :clusters,
      "applied_revision IS NULL OR applied_revision <= desired_revision",
      name: "clusters_applied_revision_not_ahead"
  end
end
