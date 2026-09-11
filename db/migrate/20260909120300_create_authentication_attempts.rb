# migration-phase: expand
#
# The login and registration throttle (Annex C §7.1, AC7).
#
# A table rather than the Rails cache, for three reasons that are all specific
# rather than stylistic. `ActionController::RateLimiting` calls
# `store.increment` and **skips the limit when the result is nil**, and this
# installation runs `:null_store` in test and `:memory_store` in development — so
# the limiter would be silently inert exactly where AC7 is proven, and per
# process in production. There is no Redis and no Solid Cache (SC/C5 moved the
# platform off Redis). And a cache may evict under pressure: an evictable rate
# limiter is one an attacker can flush by making the machine busy.
#
# The key is stored as a **digest**. A table listing every address that has ever
# tried to sign in is a disclosure on its own, and it would be a second copy of
# the account list held outside `users` (Annex C §7.3).
class CreateAuthenticationAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_attempts, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.text :scope, null: false
      t.column :key_digest, :"char(64)", null: false
      t.timestamptz :window_started_at, null: false
      t.integer :attempt_count, null: false, default: 0
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # The conflict target of the counting upsert. One atomic statement per
    # attempt, so two racing requests cannot both read the same count.
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :authentication_attempts, [ :scope, :key_digest ], unique: true
    add_index :authentication_attempts, :window_started_at

    add_check_constraint :authentication_attempts,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "authentication_attempts_id_is_ulid"

    add_check_constraint :authentication_attempts,
      "scope IN ('login_email', 'login_ip', 'registration_ip')",
      name: "authentication_attempts_scope_is_known"

    add_check_constraint :authentication_attempts,
      "key_digest ~ '^[0-9a-f]{64}$'",
      name: "authentication_attempts_key_digest_is_sha256"

    add_check_constraint :authentication_attempts,
      "attempt_count >= 0",
      name: "authentication_attempts_count_non_negative"
  end
end
