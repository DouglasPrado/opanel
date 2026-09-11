# migration-phase: expand
#
# Server-side sessions (doc 09 §15.2, doc 04 §8.2).
#
# The session is persisted so that logout and revocation are real: a credential
# the server cannot withdraw is a credential valid until it expires, whatever the
# interface says. What is stored is the **digest** of the token, never the token —
# a database copy is then not a set of usable credentials.
#
# SHA-256 rather than Argon2 for that digest, deliberately. The token is 256 bits
# of `SecureRandom`, so there is no low-entropy secret to slow an attacker down
# against, and it is read on every single request; doc 04 §9 asks for a hash
# "quando validação por hash for suficiente", and for a uniformly random value it
# is.
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :user_id, :"char(26)", null: false
      t.column :token_digest, :"char(64)", null: false
      # Absolute expiry: set once at creation and never extended (Annex C §7.1).
      t.timestamptz :expires_at, null: false
      # The basis of idle expiry, refreshed as the session is used.
      t.timestamptz :last_seen_at, null: false
      t.timestamptz :revoked_at
      # Present from this Story, always "password" until MFA (M11-05) and step-up
      # (M03-04) widen it. Declared now so the authentication context of a
      # session is a recorded fact rather than something inferred later.
      t.text :mfa_level, null: false, default: "password"
      t.inet :ip_address
      t.text :user_agent
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    add_foreign_key :sessions, :users, column: :user_id, on_delete: :cascade

    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :sessions, :token_digest, unique: true
    add_index :sessions, [ :user_id, :created_at ], order: { created_at: :desc }

    add_check_constraint :sessions,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "sessions_id_is_ulid"

    add_check_constraint :sessions,
      "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "sessions_user_id_is_ulid"

    # A column that can only hold a hex SHA-256 cannot hold a raw token by
    # accident: a writer that skipped the digest would be refused here.
    add_check_constraint :sessions,
      "token_digest ~ '^[0-9a-f]{64}$'",
      name: "sessions_token_digest_is_sha256"

    add_check_constraint :sessions,
      "mfa_level IN ('password')",
      name: "sessions_mfa_level_is_known"

    add_check_constraint :sessions,
      "user_agent IS NULL OR length(user_agent) <= 512",
      name: "sessions_user_agent_length"
  end
end
