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

ActiveRecord::Schema[8.1].define(version: 2026_09_09_120500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

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

  create_table "infrastructure_checkpoints", force: :cascade do |t|
    t.bigint "counter", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_infrastructure_checkpoints_on_name", unique: true
    t.check_constraint "counter >= 0", name: "infrastructure_checkpoints_counter_non_negative"
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
