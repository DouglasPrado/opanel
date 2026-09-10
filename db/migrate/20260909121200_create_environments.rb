# migration-phase: expand
#
# The Environment — an instance of a Project running on a Cluster (doc 09 §5.2).
#
# ## Structural invariant: Project ≠ Cluster child
#
# doc 01 §5.1 makes clear: a Project is not hierarchically under its infrastructure.
# The Environment is what chooses where each Project runs. This table references both,
# and neither the Project nor the Cluster table references the other — the many-to-many
# would be backwards.
#
# ## Revision tracking
#
# `desired_revision` increments each time the operator changes intent.
# `applied_revision` is where the reconciler last got to, and stays null until M01-18.
# The schema forbids `applied_revision > desired_revision`.
#
# ## Status is observation, not claim
#
# Like Cluster (doc 06 §14.1), status holds the last observation from the reconciler.
# There is no boolean health column; neither is a stored state that a controller sets.
# Derived status methods compute from the observations present.
#
# ## `auto_promote_secrets` defaults to false in PRODUCTION (AC5)
#
# M03 will require PRODUCTION to pin Secrets explicitly. M01 lays the foundation: when
# an Environment is `PRODUCTION`, `auto_promote_secrets` defaults to false and the
# database refuses true in that state. The CHECK makes it impossible to "forget" to set
# it in a form.
class CreateEnvironments < ActiveRecord::Migration[8.1]
  def change
    create_table :environments, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :project_id, :"char(26)", null: false
      t.column :cluster_id, :"char(26)", null: false
      # Denormalized for efficient tenant-scoped queries (M01-04 AC5).
      t.column :team_id, :"char(26)", null: false
      t.text :name, null: false
      t.text :slug, null: false
      # Type of Environment (PRODUCTION, HOMOLOGATION, DEVELOPMENT, PREVIEW, CUSTOM).
      # "Type" because "environment" is already the entity name.
      t.text :type, null: false, default: "DEVELOPMENT"

      # Forward reference to network overlay (M01-17); nullable until then.
      t.column :network_id, :"char(26)"

      # doc 09 §5.2. `false` by default in PRODUCTION; the CHECK enforces the rule.
      t.boolean :auto_promote_secrets, null: false, default: false

      # Status: the last thing the reconciler observed.
      t.text :status, null: false, default: "PROVISIONING"

      # Revision tracking (doc 09 §17). `applied_revision` is null until M01-18.
      t.bigint :desired_revision, null: false, default: 1
      t.bigint :applied_revision

      t.timestamptz :deleted_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # Foreign keys with RESTRICT, like other tenant resources (doc 09 §25).
    add_foreign_key :environments, :projects, column: :project_id, on_delete: :restrict
    add_foreign_key :environments, :clusters, column: :cluster_id, on_delete: :restrict
    add_foreign_key :environments, :teams, column: :team_id, on_delete: :restrict

    # AC2 — doc 09 §18. Partial: a deleted Environment must not hold a slug forever.
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :environments, %i[project_id slug], unique: true, where: "deleted_at IS NULL",
      name: "index_environments_unique_slug_per_project_when_not_deleted"

    # AC6 — keyset pagination by project. The cursor is the ULID.
    #
    # migration-index-review: new empty table.
    add_index :environments, %i[project_id id], name: "index_environments_on_project_id_and_id"

    # For efficient queries through cluster.
    #
    # migration-index-review: new empty table.
    add_index :environments, :cluster_id, name: "index_environments_on_cluster_id"

    # Tenant scoping (M01-04 AC5): team_id is denormalized to avoid joins.
    #
    # migration-index-review: new empty table.
    add_index :environments, :team_id, name: "index_environments_on_team_id"

    # ULID format checks.
    add_check_constraint :environments,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "environments_id_is_ulid"

    add_check_constraint :environments,
      "project_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "environments_project_id_is_ulid"

    add_check_constraint :environments,
      "cluster_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "environments_cluster_id_is_ulid"

    add_check_constraint :environments,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "environments_team_id_is_ulid"

    add_check_constraint :environments,
      "network_id IS NULL OR network_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "environments_network_id_is_ulid_or_null"

    # Slug must be a URL segment, unique per Project (enforced above).
    add_check_constraint :environments,
      "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' AND length(slug) BETWEEN 2 AND 63",
      name: "environments_slug_format"

    # Name must be present.
    add_check_constraint :environments,
      "btrim(name) <> '' AND length(name) <= 120",
      name: "environments_name_present"

    # Type: the five documented options.
    add_check_constraint :environments,
      "type IN ('PRODUCTION', 'HOMOLOGATION', 'DEVELOPMENT', 'PREVIEW', 'CUSTOM')",
      name: "environments_type_is_known"

    # AC5: PRODUCTION defaults to false and must stay false.
    add_check_constraint :environments,
      "type <> 'PRODUCTION' OR auto_promote_secrets = false",
      name: "environments_production_no_auto_promote"

    # Status: the five states of doc 09 §5.2.
    add_check_constraint :environments,
      "status IN ('PROVISIONING', 'READY', 'DEGRADED', 'PAUSED', 'DELETING')",
      name: "environments_status_is_known"

    # Revision: applied cannot exceed desired.
    add_check_constraint :environments,
      "applied_revision IS NULL OR applied_revision <= desired_revision",
      name: "environments_applied_revision_not_ahead"
  end
end
