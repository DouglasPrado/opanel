# migration-phase: expand
#
# The Service — the operator's intent about a workload (doc 09 §5.3).
#
# ## Structural relationships
#
# Service belongs to Environment which belongs to Project which belongs to Team.
# The tenancy boundary flows through all three. A Service has all the fields needed
# to express runtime intent: image, replicas, ports, resources, health check, and
# placement — but Operation and Outbox are part of M01-13, and actual runtime
# observation is part of M01-19.
#
# ## Image reference
#
# The `image_ref` column holds the OCI reference as the user provided it, or after
# normalization if the tag was mutable. Resolution from tag to digest happens in the
# CreateService command (AC7), and the digest is stored here so the reconciler can
# use the immutable artifact. In M06 (Releases), this becomes a foreign key to Release.
#
# ## Technical naming
#
# `technical_name` is deterministic and derived from team/project/environment/service
# IDs, but the product never depends on it as the primary identifier (doc 09 §5.3).
# It is used to name the Swarm service when the service is deployed.
#
# ## Revision tracking
#
# Like Environment, `desired_revision` increments when the operator changes intent,
# and `applied_revision` tracks where the reconciler got to. The schema forbids
# applied_revision > desired_revision.
#
# ## Status is observation
#
# Like Environment, status holds the last observation from the reconciler (M01-18).
# It is not a field the controller sets, and it starts as DRAFT until the first
# reconciliation run.
#
class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :environment_id, :"char(26)", null: false
      # Denormalized for efficient tenant-scoped queries (M01-04 AC5).
      t.column :team_id, :"char(26)", null: false

      t.text :name, null: false
      t.text :slug, null: false
      # Service type: WEB, WORKER, CRON, TASK, DATABASE, CACHE, etc.
      t.text :service_type, null: false, default: "WEB"

      # OCI image reference. The user provides imageRef; if it contains a mutable
      # tag, CreateService resolves it to a digest. The digest is what gets deployed.
      t.text :image_ref, null: false


      # Image digest (SHA256). Populated only when the user pins an explicit @sha256:
      # digest; left NULL for a mutable tag. Resolution of mutable tags to digest is
      # performed by the reconciler in M01-18 (SC-21; resolution belongs to M01-18).
      t.text :image_digest
      # Runtime configuration.
      t.bigint :replicas, null: false, default: 1
      t.text :command
      t.text :args
      t.jsonb :ports, null: false, default: {}
      t.jsonb :health_check

      # Resource constraints. All may be null (warning issued), or only one side
      # specified (implicit unbounded).
      t.bigint :cpu_reservation
      t.bigint :cpu_limit
      t.bigint :memory_reservation
      t.bigint :memory_limit

      # Placement and scheduling (basic for M01-12; advanced placement is future).
      t.jsonb :constraints

      # Derived technical name for Swarm, deterministic from IDs.
      t.text :technical_name, null: false

      # Status: the last thing the reconciler observed.
      t.text :status, null: false, default: "DRAFT"

      # Revision tracking (doc 09 §17). applied_revision is null until M01-18.
      t.bigint :desired_revision, null: false, default: 1
      t.bigint :applied_revision

      t.timestamptz :deleted_at
      t.timestamptz :archived_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # Foreign keys with RESTRICT, like other tenant resources (doc 09 §25).
    add_foreign_key :services, :environments, column: :environment_id, on_delete: :restrict
    add_foreign_key :services, :teams, column: :team_id, on_delete: :restrict

    # AC2 — doc 09 §18. Partial: a deleted Service must not hold a slug forever.
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :services, %i[environment_id slug], unique: true, where: "deleted_at IS NULL",
      name: "index_services_unique_slug_per_environment_when_not_deleted"

    # AC6 — keyset pagination by environment.
    #
    # migration-index-review: new empty table.
    add_index :services, %i[environment_id id], name: "index_services_on_environment_id_and_id"

    # Tenant scoping (M01-04 AC5): team_id is denormalized to avoid joins.
    #
    # migration-index-review: new empty table.
    add_index :services, :team_id, name: "index_services_on_team_id"

    # ULID format checks.
    add_check_constraint :services,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "services_id_is_ulid"

    add_check_constraint :services,
      "environment_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "services_environment_id_is_ulid"

    add_check_constraint :services,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "services_team_id_is_ulid"

    # Slug must be a URL segment, unique per Environment.
    add_check_constraint :services,
      "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' AND length(slug) BETWEEN 2 AND 63",
      name: "services_slug_format"

    # Name must be present and not too long.
    add_check_constraint :services,
      "btrim(name) <> '' AND length(name) <= 120",
      name: "services_name_present"

    # Service type must be a known value.
    add_check_constraint :services,
      "service_type IN ('WEB', 'WORKER', 'CRON', 'TASK', 'DATABASE', 'CACHE')",
      name: "services_type_is_known"

    # Image reference is required and not empty.
    add_check_constraint :services,
      "btrim(image_ref) <> ''",
      name: "services_image_ref_present"

    # Replicas must be positive.
    add_check_constraint :services,
      "replicas > 0",
      name: "services_replicas_positive"

    # Resource constraints: if both are set, limit >= reservation.
    add_check_constraint :services,
      "cpu_limit IS NULL OR cpu_reservation IS NULL OR cpu_limit >= cpu_reservation",
      name: "services_cpu_limit_gte_reservation"

    add_check_constraint :services,
      "memory_limit IS NULL OR memory_reservation IS NULL OR memory_limit >= memory_reservation",
      name: "services_memory_limit_gte_reservation"

    # Status must be a known value.
    add_check_constraint :services,
      "status IN ('DRAFT', 'PROVISIONING', 'RUNNING', 'DEGRADED', 'STOPPED', 'DELETING')",
      name: "services_status_is_known"

    # Revision: applied cannot exceed desired.
    add_check_constraint :services,
      "applied_revision IS NULL OR applied_revision <= desired_revision",
      name: "services_applied_revision_not_ahead"
  end
end
