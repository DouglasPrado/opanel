# migration-phase: expand
#
# The first domain table, and therefore the one that fixes the identifier
# convention for every table after it (ADR-0002, accepted 2026-09-08).
#
# `id char(26)`, generated in the application, holding a ULID. The `CHECK` beside
# it is load-bearing rather than decorative: `db/schema.rb` round-trips
# `char(26)` as `varchar(26)` because the PostgreSQL adapter aliases `bpchar` to
# `varchar`, so a database built from the dump has a slightly different column
# type from one built by this migration. With every value exactly 26 Crockford
# characters the two are indistinguishable in storage, comparison, index and
# join, and `bpchar` padding never happens — the constraint is what makes that
# true rather than hoped for. Recorded as SC-17.
#
# Every enumeration is `text` + `CHECK`, never a PostgreSQL ENUM type: adding a
# value later is then an ordinary expand migration rather than an `ALTER TYPE`
# that cannot run inside a transaction.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :email, :citext, null: false
      t.text :display_name, null: false
      t.text :password_digest, null: false
      t.text :status, null: false, default: "ACTIVE"
      # `timestamptz`, not Rails' default `timestamp`: doc 09 stores every
      # timestamp in UTC with its zone, and an expiry compared against a naive
      # column is an expiry that depends on the server's locale.
      t.timestamptz :email_verified_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # UNCONDITIONAL, deliberately. A partial unique excluding DELETED_PENDING
    # would let the address of an account still in retention be taken over in
    # silence, which is exactly what doc 09 §3.1 forbids: "não reutilizar
    # silenciosamente enquanto conta estiver em retenção".
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :users, :email, unique: true

    add_check_constraint :users,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "users_id_is_ulid"

    add_check_constraint :users,
      "length(email) BETWEEN 3 AND 254",
      name: "users_email_length"

    add_check_constraint :users,
      "btrim(display_name) <> '' AND length(display_name) <= 120",
      name: "users_display_name_present"

    # The KDF is a property of the stored value, so the database refuses a
    # digest that is not Argon2id — including one written by something that
    # bypasses the model entirely (Annex B §13, Annex C §7.1).
    add_check_constraint :users,
      "password_digest LIKE '$argon2id$%'",
      name: "users_password_digest_is_argon2id"

    add_check_constraint :users,
      "status IN ('ACTIVE', 'SUSPENDED', 'DELETED_PENDING')",
      name: "users_status_is_known"
  end
end
