# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_10_000800) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_logs", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.text "action", null: false
    t.string "actor_id", limit: 26
    t.text "actor_type", null: false
    t.jsonb "after", default: {}, null: false
    t.jsonb "before", default: {}, null: false
    t.text "correlation_id", null: false
    t.timestamptz "created_at", null: false
    t.string "environment_id", limit: 26
    t.inet "ip"
    t.string "operation_id", limit: 26
    t.text "request_id", null: false
    t.string "resource_id", limit: 26
    t.text "resource_type", null: false
    t.text "result", null: false
    t.integer "revision", default: 1, null: false
    t.string "team_id", limit: 26
    t.text "user_agent"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_type", "resource_id", "created_at"], name: "index_audit_logs_on_resource_and_created_at", order: { created_at: :desc }
    t.index ["team_id", "created_at"], name: "index_audit_logs_on_team_id_and_created_at", order: { created_at: :desc }
    t.check_constraint "action ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$'::text", name: "audit_logs_action_is_namespaced"
    t.check_constraint "actor_type = ANY (ARRAY['USER'::text, 'API_TOKEN'::text, 'SYSTEM'::text, 'RECOVERY'::text])", name: "audit_logs_actor_type_is_known"
    t.check_constraint "btrim(correlation_id) <> ''::text", name: "audit_logs_correlation_id_present"
    t.check_constraint "btrim(request_id) <> ''::text", name: "audit_logs_request_id_present"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "audit_logs_id_is_ulid"
    t.check_constraint "result = ANY (ARRAY['SUCCESS'::text, 'DENIED'::text, 'FAILED'::text])", name: "audit_logs_result_is_known"
    t.check_constraint "revision = 1", name: "audit_logs_are_append_only"
  end

  create_table "authentication_attempts", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.timestamptz "created_at", null: false
    t.string "key_digest", limit: 64, null: false
    t.text "scope", null: false
    t.timestamptz "updated_at", null: false
    t.timestamptz "window_started_at", null: false
    t.index ["scope", "key_digest"], name: "index_authentication_attempts_on_scope_and_key_digest", unique: true
    t.index ["window_started_at"], name: "index_authentication_attempts_on_window_started_at"
    t.check_constraint "attempt_count >= 0", name: "authentication_attempts_count_non_negative"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "authentication_attempts_id_is_ulid"
    t.check_constraint "key_digest ~ '^[0-9a-f]{64}$'::text", name: "authentication_attempts_key_digest_is_sha256"
    t.check_constraint "scope = ANY (ARRAY['login_email'::text, 'login_ip'::text, 'registration_ip'::text])", name: "authentication_attempts_scope_is_known"
  end

  create_table "clusters", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.text "advertise_address"
    t.bigint "applied_revision"
    t.timestamptz "created_at", null: false
    t.timestamptz "deleted_at"
    t.bigint "desired_revision", default: 1, null: false
    t.text "name", null: false
    t.timestamptz "observed_at"
    t.text "slug", null: false
    t.text "status", default: "PROVISIONING", null: false
    t.text "swarm_id"
    t.string "team_id", limit: 26, null: false
    t.text "unreachable_reason"
    t.timestamptz "updated_at", null: false
    t.index ["swarm_id"], name: "index_clusters_unique_swarm_id_when_known", unique: true, where: "(swarm_id IS NOT NULL)"
    t.index ["team_id", "id"], name: "index_clusters_on_team_id_and_id"
    t.index ["team_id", "slug"], name: "index_clusters_unique_slug_per_team_when_not_deleted", unique: true, where: "(deleted_at IS NULL)"
    t.check_constraint "applied_revision IS NULL OR applied_revision <= desired_revision", name: "clusters_applied_revision_not_ahead"
    t.check_constraint "btrim(name) <> ''::text AND length(name) <= 120", name: "clusters_name_present"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "clusters_id_is_ulid"
    t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'::text AND length(slug) >= 2 AND length(slug) <= 63", name: "clusters_slug_format"
    t.check_constraint "status = 'PROVISIONING'::text OR observed_at IS NOT NULL", name: "clusters_observed_status_has_a_timestamp"
    t.check_constraint "status = ANY (ARRAY['PROVISIONING'::text, 'READY'::text, 'DEGRADED'::text, 'MAINTENANCE'::text, 'UNREACHABLE'::text, 'DELETING'::text])", name: "clusters_status_is_known"
    t.check_constraint "swarm_id IS NULL OR swarm_id ~ '^[a-z0-9]{20,32}$'::text", name: "clusters_swarm_id_shape"
    t.check_constraint "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "clusters_team_id_is_ulid"
  end

  create_table "environments", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.bigint "applied_revision"
    t.boolean "auto_promote_secrets", default: false, null: false
    t.string "cluster_id", limit: 26, null: false
    t.timestamptz "created_at", null: false
    t.timestamptz "deleted_at"
    t.bigint "desired_revision", default: 1, null: false
    t.text "name", null: false
    t.string "network_id", limit: 26
    t.string "project_id", limit: 26, null: false
    t.text "slug", null: false
    t.text "status", default: "PROVISIONING", null: false
    t.string "team_id", limit: 26, null: false
    t.text "type", default: "DEVELOPMENT", null: false
    t.timestamptz "updated_at", null: false
    t.index ["cluster_id"], name: "index_environments_on_cluster_id"
    t.index ["project_id", "id"], name: "index_environments_on_project_id_and_id"
    t.index ["project_id", "slug"], name: "index_environments_unique_slug_per_project_when_not_deleted", unique: true, where: "(deleted_at IS NULL)"
    t.index ["team_id"], name: "index_environments_on_team_id"
    t.check_constraint "applied_revision IS NULL OR applied_revision <= desired_revision", name: "environments_applied_revision_not_ahead"
    t.check_constraint "btrim(name) <> ''::text AND length(name) <= 120", name: "environments_name_present"
    t.check_constraint "cluster_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "environments_cluster_id_is_ulid"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "environments_id_is_ulid"
    t.check_constraint "network_id IS NULL OR network_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "environments_network_id_is_ulid_or_null"
    t.check_constraint "project_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "environments_project_id_is_ulid"
    t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'::text AND length(slug) >= 2 AND length(slug) <= 63", name: "environments_slug_format"
    t.check_constraint "status = ANY (ARRAY['PROVISIONING'::text, 'READY'::text, 'DEGRADED'::text, 'PAUSED'::text, 'DELETING'::text])", name: "environments_status_is_known"
    t.check_constraint "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "environments_team_id_is_ulid"
    t.check_constraint "type <> 'PRODUCTION'::text OR auto_promote_secrets = false", name: "environments_production_no_auto_promote"
    t.check_constraint "type = ANY (ARRAY['PRODUCTION'::text, 'HOMOLOGATION'::text, 'DEVELOPMENT'::text, 'PREVIEW'::text, 'CUSTOM'::text])", name: "environments_type_is_known"
  end

  create_table "inbox_events", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "processed_at"
    t.string "result_ref"
    t.string "source", null: false
    t.string "source_event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "source_event_id"], name: "index_inbox_events_source_event_id_unique", unique: true
    t.index ["source"], name: "index_inbox_events_on_source"
    t.index ["source_event_id"], name: "index_inbox_events_on_source_event_id"
  end

  create_table "infrastructure_checkpoints", force: :cascade do |t|
    t.bigint "counter", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_infrastructure_checkpoints_on_name", unique: true
    t.check_constraint "counter >= 0", name: "infrastructure_checkpoints_counter_non_negative"
  end

  create_table "instance_roles", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "granted_by_bootstrap"
    t.timestamptz "revoked_at"
    t.text "role", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", limit: 26, null: false
    t.index ["granted_by_bootstrap"], name: "index_instance_roles_single_bootstrap", unique: true, where: "granted_by_bootstrap"
    t.index ["role"], name: "index_instance_roles_active_by_role", where: "(revoked_at IS NULL)"
    t.index ["user_id", "role"], name: "index_instance_roles_one_active_grant_per_user_and_role", unique: true, where: "(revoked_at IS NULL)"
    t.check_constraint "granted_by_bootstrap IS NULL OR granted_by_bootstrap", name: "instance_roles_bootstrap_marker_is_true_or_absent"
    t.check_constraint "granted_by_bootstrap IS NULL OR role = 'INSTANCE_ADMIN'::text", name: "instance_roles_bootstrap_is_admin"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "instance_roles_id_is_ulid"
    t.check_constraint "role = ANY (ARRAY['INSTANCE_ADMIN'::text, 'INSTANCE_OPERATOR'::text, 'INSTANCE_AUDITOR'::text])", name: "instance_roles_role_is_known"
    t.check_constraint "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "instance_roles_user_id_is_ulid"
  end

  create_table "node_observations", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.text "availability"
    t.timestamptz "created_at", null: false
    t.text "engine_version"
    t.string "node_id", limit: 26, null: false
    t.timestamptz "observed_at", null: false
    t.jsonb "resources"
    t.text "status", null: false
    t.index ["node_id", "observed_at"], name: "index_node_observations_latest_per_node", order: { observed_at: :desc }
    t.check_constraint "availability IS NULL OR (availability = ANY (ARRAY['ACTIVE'::text, 'PAUSE'::text, 'DRAIN'::text]))", name: "node_observations_availability_is_valid"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "node_observations_id_is_ulid"
    t.check_constraint "node_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "node_observations_node_id_is_ulid"
    t.check_constraint "status = ANY (ARRAY['JOINING'::text, 'READY'::text, 'DEGRADED'::text, 'DOWN'::text, 'REMOVING'::text])", name: "node_observations_status_is_known"
  end

  create_table "nodes", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.text "advertise_address"
    t.text "availability", default: "ACTIVE", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.string "cluster_id", limit: 26, null: false
    t.timestamptz "created_at", null: false
    t.timestamptz "deleted_at"
    t.text "hostname", null: false
    t.jsonb "labels", default: {}, null: false
    t.timestamptz "last_seen_at"
    t.text "private_address"
    t.text "public_address"
    t.text "role", null: false
    t.text "status", default: "JOINING", null: false
    t.text "swarm_node_id", null: false
    t.timestamptz "updated_at", null: false
    t.index ["cluster_id", "id"], name: "index_nodes_on_cluster_id_and_id"
    t.index ["cluster_id", "status"], name: "index_nodes_on_cluster_id_and_status"
    t.index ["cluster_id", "swarm_node_id"], name: "index_nodes_unique_swarm_node_id_per_cluster", unique: true
    t.check_constraint "availability = ANY (ARRAY['ACTIVE'::text, 'PAUSE'::text, 'DRAIN'::text])", name: "nodes_availability_is_known"
    t.check_constraint "btrim(hostname) <> ''::text", name: "nodes_hostname_present"
    t.check_constraint "btrim(swarm_node_id) <> ''::text", name: "nodes_swarm_node_id_present"
    t.check_constraint "cluster_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "nodes_cluster_id_is_ulid"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "nodes_id_is_ulid"
    t.check_constraint "role = ANY (ARRAY['MANAGER'::text, 'WORKER'::text])", name: "nodes_role_is_known"
    t.check_constraint "status = ANY (ARRAY['JOINING'::text, 'READY'::text, 'DEGRADED'::text, 'DOWN'::text, 'REMOVING'::text])", name: "nodes_status_is_known"
  end

  create_table "operation_attempts", id: :string, force: :cascade do |t|
    t.integer "attempt_number", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "executor_id"
    t.datetime "finished_at"
    t.jsonb "metadata", default: {}
    t.string "operation_id", null: false
    t.string "outcome"
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_id", "attempt_number"], name: "index_operation_attempts_on_operation_id_and_attempt_number", unique: true
    t.index ["operation_id"], name: "index_operation_attempts_on_operation_id"
    t.check_constraint "attempt_number >= 1", name: "attempt_number_positive"
  end

  create_table "operations", id: :string, force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.bigint "desired_revision", null: false
    t.string "error_code"
    t.bigint "fencing_token"
    t.datetime "finished_at"
    t.string "idempotency_key"
    t.string "lease_owner"
    t.datetime "lease_until"
    t.datetime "next_attempt_at"
    t.jsonb "payload", default: {}, null: false
    t.string "request_id"
    t.string "requested_by"
    t.string "resource_id", null: false
    t.string "resource_type", null: false
    t.datetime "stalled_at"
    t.string "stalled_reason"
    t.datetime "started_at"
    t.string "status", null: false
    t.string "team_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id"], name: "index_operations_on_resource_id"
    t.index ["resource_type", "status", "created_at"], name: "index_operations_by_resource_status"
    t.index ["resource_type", "status", "next_attempt_at"], name: "index_operations_for_retry_dispatch"
    t.index ["resource_type"], name: "index_operations_on_resource_type"
    t.index ["stalled_at"], name: "index_operations_stalled"
    t.index ["status"], name: "index_operations_on_status"
    t.index ["team_id", "resource_type", "resource_id", "type", "idempotency_key"], name: "index_operations_idempotency_doc_07_6_1", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["team_id"], name: "index_operations_on_team_id"
    t.index ["type"], name: "index_operations_on_type"
    t.check_constraint "attempt_count >= 0", name: "attempt_count_non_negative"
    t.check_constraint "lease_owner IS NULL AND lease_until IS NULL OR lease_owner IS NOT NULL AND lease_until IS NOT NULL", name: "lease_pair_coherent"
    t.check_constraint "payload ? 'schemaVersion'::text", name: "payload_has_schema_version"
    t.check_constraint "status::text = ANY (ARRAY['PENDING'::character varying, 'QUEUED'::character varying, 'RUNNING'::character varying, 'WAITING_RUNTIME'::character varying, 'VERIFYING'::character varying, 'SUCCEEDED'::character varying, 'RETRYABLE'::character varying, 'FAILED'::character varying, 'CANCELED'::character varying, 'SUPERSEDED'::character varying, 'TIMED_OUT'::character varying]::text[])", name: "status_in_valid_set"
  end

  create_table "outbox_events", id: :string, force: :cascade do |t|
    t.string "aggregate_id", null: false
    t.string "aggregate_type", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.string "partition_key"
    t.jsonb "payload", default: {}, null: false
    t.datetime "published_at"
    t.integer "schema_version", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["aggregate_id"], name: "index_outbox_events_on_aggregate_id"
    t.index ["aggregate_type"], name: "index_outbox_events_on_aggregate_type"
    t.index ["published_at", "occurred_at"], name: "index_outbox_events_for_publisher"
    t.index ["published_at"], name: "index_outbox_events_unpublished", where: "(published_at IS NULL)"
    t.check_constraint "schema_version > 0", name: "schema_version_positive"
  end

  create_table "projects", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.timestamptz "created_at", null: false
    t.string "default_environment_id", limit: 26
    t.timestamptz "deleted_at"
    t.text "description"
    t.text "name", null: false
    t.text "slug", null: false
    t.text "status", default: "ACTIVE", null: false
    t.string "team_id", limit: 26, null: false
    t.timestamptz "updated_at", null: false
    t.index ["team_id", "id"], name: "index_projects_on_team_id_and_id"
    t.index ["team_id", "slug"], name: "index_projects_unique_slug_per_team_when_not_deleted", unique: true, where: "(deleted_at IS NULL)"
    t.check_constraint "btrim(name) <> ''::text AND length(name) <= 120", name: "projects_name_present"
    t.check_constraint "default_environment_id IS NULL OR default_environment_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "projects_default_environment_id_is_ulid"
    t.check_constraint "description IS NULL OR length(description) <= 2000", name: "projects_description_length"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "projects_id_is_ulid"
    t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'::text AND length(slug) >= 2 AND length(slug) <= 63", name: "projects_slug_format"
    t.check_constraint "status = ANY (ARRAY['ACTIVE'::text, 'ARCHIVED'::text, 'DELETING'::text])", name: "projects_status_is_known"
    t.check_constraint "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "projects_team_id_is_ulid"
  end

  create_table "resource_locks", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "fencing_token", default: 0, null: false
    t.datetime "lease_until", null: false
    t.string "owner", null: false
    t.text "scope_key", null: false
    t.string "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_key"], name: "index_resource_locks_scope_key_unique", unique: true
    t.index ["team_id"], name: "index_resource_locks_on_team_id"
    t.check_constraint "btrim(owner::text) <> ''::text", name: "resource_locks_owner_present"
    t.check_constraint "btrim(scope_key) <> ''::text", name: "resource_locks_scope_key_present"
    t.check_constraint "fencing_token >= 0", name: "resource_locks_fencing_token_non_negative"
    t.check_constraint "id::text ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "resource_locks_id_is_ulid"
    t.check_constraint "team_id::text ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "resource_locks_team_id_is_ulid"
  end

  create_table "services", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.bigint "applied_revision"
    t.timestamptz "archived_at"
    t.text "args"
    t.text "command"
    t.jsonb "constraints"
    t.bigint "cpu_limit"
    t.bigint "cpu_reservation"
    t.timestamptz "created_at", null: false
    t.timestamptz "deleted_at"
    t.bigint "desired_revision", default: 1, null: false
    t.string "environment_id", limit: 26, null: false
    t.jsonb "health_check"
    t.text "image_digest"
    t.text "image_ref", null: false
    t.bigint "memory_limit"
    t.bigint "memory_reservation"
    t.text "name", null: false
    t.jsonb "ports", default: {}, null: false
    t.bigint "replicas", default: 1, null: false
    t.text "service_type", default: "WEB", null: false
    t.text "slug", null: false
    t.text "status", default: "DRAFT", null: false
    t.string "team_id", limit: 26, null: false
    t.text "technical_name", null: false
    t.timestamptz "updated_at", null: false
    t.index ["environment_id", "id"], name: "index_services_on_environment_id_and_id"
    t.index ["environment_id", "slug"], name: "index_services_unique_slug_per_environment_when_not_deleted", unique: true, where: "(deleted_at IS NULL)"
    t.index ["team_id"], name: "index_services_on_team_id"
    t.check_constraint "applied_revision IS NULL OR applied_revision <= desired_revision", name: "services_applied_revision_not_ahead"
    t.check_constraint "btrim(image_ref) <> ''::text", name: "services_image_ref_present"
    t.check_constraint "btrim(name) <> ''::text AND length(name) <= 120", name: "services_name_present"
    t.check_constraint "cpu_limit IS NULL OR cpu_reservation IS NULL OR cpu_limit >= cpu_reservation", name: "services_cpu_limit_gte_reservation"
    t.check_constraint "environment_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "services_environment_id_is_ulid"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "services_id_is_ulid"
    t.check_constraint "memory_limit IS NULL OR memory_reservation IS NULL OR memory_limit >= memory_reservation", name: "services_memory_limit_gte_reservation"
    t.check_constraint "replicas > 0", name: "services_replicas_positive"
    t.check_constraint "service_type = ANY (ARRAY['WEB'::text, 'WORKER'::text, 'CRON'::text, 'TASK'::text, 'DATABASE'::text, 'CACHE'::text])", name: "services_type_is_known"
    t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'::text AND length(slug) >= 2 AND length(slug) <= 63", name: "services_slug_format"
    t.check_constraint "status = ANY (ARRAY['DRAFT'::text, 'PROVISIONING'::text, 'RUNNING'::text, 'DEGRADED'::text, 'STOPPED'::text, 'DELETING'::text])", name: "services_status_is_known"
    t.check_constraint "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "services_team_id_is_ulid"
  end

  create_table "sessions", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.timestamptz "created_at", null: false
    t.timestamptz "expires_at", null: false
    t.inet "ip_address"
    t.timestamptz "last_seen_at", null: false
    t.text "mfa_level", default: "password", null: false
    t.timestamptz "revoked_at"
    t.string "token_digest", limit: 64, null: false
    t.timestamptz "updated_at", null: false
    t.text "user_agent"
    t.string "user_id", limit: 26, null: false
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id", "created_at"], name: "index_sessions_on_user_id_and_created_at", order: { created_at: :desc }
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "sessions_id_is_ulid"
    t.check_constraint "mfa_level = 'password'::text", name: "sessions_mfa_level_is_known"
    t.check_constraint "token_digest ~ '^[0-9a-f]{64}$'::text", name: "sessions_token_digest_is_sha256"
    t.check_constraint "user_agent IS NULL OR length(user_agent) <= 512", name: "sessions_user_agent_length"
    t.check_constraint "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "sessions_user_id_is_ulid"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "team_members", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.timestamptz "created_at", null: false
    t.string "invited_by", limit: 26
    t.timestamptz "joined_at"
    t.text "role", null: false
    t.text "status", null: false
    t.string "team_id", limit: 26, null: false
    t.timestamptz "updated_at", null: false
    t.string "user_id", limit: 26, null: false
    t.index ["team_id", "user_id", "role", "status"], name: "index_team_members_owner_reference", unique: true
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_one_active_owner_per_team", unique: true, where: "((role = 'OWNER'::text) AND (status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text])))"
    t.index ["user_id", "status"], name: "index_team_members_on_user_id_and_status"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "team_members_id_is_ulid"
    t.check_constraint "invited_by IS NULL OR invited_by ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "team_members_invited_by_is_ulid"
    t.check_constraint "role = ANY (ARRAY['OWNER'::text, 'ADMIN'::text, 'DEVELOPER'::text, 'VIEWER'::text])", name: "team_members_role_is_known"
    t.check_constraint "status = 'INVITED'::text OR joined_at IS NOT NULL", name: "team_members_joined_at_present_once_accepted"
    t.check_constraint "status = ANY (ARRAY['INVITED'::text, 'ACTIVE'::text, 'SUSPENDED'::text, 'REMOVED'::text])", name: "team_members_status_is_known"
    t.check_constraint "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "team_members_team_id_is_ulid"
    t.check_constraint "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "team_members_user_id_is_ulid"
  end

  create_table "teams", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.timestamptz "created_at", null: false
    t.timestamptz "deleted_at"
    t.text "name", null: false
    t.virtual "owner_membership_status", type: :text, as: "\nCASE\n    WHEN (status = 'OWNERSHIP_RECOVERY_REQUIRED'::text) THEN 'SUSPENDED'::text\n    ELSE 'ACTIVE'::text\nEND", stored: true
    t.virtual "owner_role", type: :text, as: "'OWNER'::text", stored: true
    t.string "owner_user_id", limit: 26, null: false
    t.text "slug", null: false
    t.text "status", default: "ACTIVE", null: false
    t.timestamptz "updated_at", null: false
    t.index ["owner_user_id"], name: "index_teams_on_owner_user_id"
    t.index ["slug"], name: "index_teams_unique_slug_when_not_deleted", unique: true, where: "(deleted_at IS NULL)"
    t.check_constraint "btrim(name) <> ''::text AND length(name) <= 120", name: "teams_name_present"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "teams_id_is_ulid"
    t.check_constraint "owner_user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "teams_owner_user_id_is_ulid"
    t.check_constraint "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'::text AND length(slug) >= 2 AND length(slug) <= 63", name: "teams_slug_format"
    t.check_constraint "status = ANY (ARRAY['ACTIVE'::text, 'OWNERSHIP_RECOVERY_REQUIRED'::text])", name: "teams_status_is_known"
  end

  create_table "users", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.timestamptz "created_at", null: false
    t.text "display_name", null: false
    t.citext "email", null: false
    t.timestamptz "email_verified_at"
    t.text "password_digest", null: false
    t.text "status", default: "ACTIVE", null: false
    t.timestamptz "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "btrim(display_name) <> ''::text AND length(display_name) <= 120", name: "users_display_name_present"
    t.check_constraint "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'::text", name: "users_id_is_ulid"
    t.check_constraint "length(email::text) >= 3 AND length(email::text) <= 254", name: "users_email_length"
    t.check_constraint "password_digest ~~ '$argon2id$%'::text", name: "users_password_digest_is_argon2id"
    t.check_constraint "status = ANY (ARRAY['ACTIVE'::text, 'SUSPENDED'::text, 'DELETED_PENDING'::text])", name: "users_status_is_known"
  end

  add_foreign_key "clusters", "teams", on_delete: :restrict
  add_foreign_key "environments", "clusters", on_delete: :restrict
  add_foreign_key "environments", "projects", on_delete: :restrict
  add_foreign_key "environments", "teams", on_delete: :restrict
  add_foreign_key "instance_roles", "users", on_delete: :restrict
  add_foreign_key "node_observations", "nodes", on_delete: :cascade
  add_foreign_key "nodes", "clusters", on_delete: :restrict
  add_foreign_key "operation_attempts", "operations"
  add_foreign_key "operations", "teams", on_delete: :restrict
  add_foreign_key "projects", "teams", on_delete: :restrict
  add_foreign_key "resource_locks", "teams", on_delete: :restrict
  add_foreign_key "services", "environments", on_delete: :restrict
  add_foreign_key "services", "teams", on_delete: :restrict
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "team_members", "teams", on_delete: :restrict
  add_foreign_key "team_members", "users", column: "invited_by", on_delete: :restrict
  add_foreign_key "team_members", "users", on_delete: :restrict
  add_foreign_key "teams", "team_members", column: ["id", "owner_user_id", "owner_role", "owner_membership_status"], primary_key: ["team_id", "user_id", "role", "status"], name: "fk_teams_active_owner_membership", deferrable: :deferred
  add_foreign_key "teams", "users", column: "owner_user_id", on_delete: :restrict
end
