# migration-phase: expand
#
# The tenant of the product (doc 09 §3.2, doc 04 §2).
#
# `owner_user_id` is denormalized ownership: the OWNER is *also* a row in
# `team_members`, and doc 04 §3.2 requires the two to agree at all times. The
# constraint that makes them agree is a composite foreign key added in the next
# migration, once `team_members` exists — the circularity is deliberate and is
# resolved by that key being DEFERRABLE, so one transaction can write both rows.
#
# `owner_role` and `owner_membership_status` exist **for that foreign key and for
# nothing else**. They are not domain data: no code reads them, no serializer
# exposes them, and neither can be written, because both are
# `GENERATED ALWAYS AS ... STORED`. PostgreSQL will not accept a partial index as
# the target of a foreign key, so the obvious key —
# `teams(id, owner_user_id) → team_members(team_id, user_id)` restricted to
# OWNER+ACTIVE — does not compile. Materializing the two constants on this side
# turns the restriction into ordinary columns, and the key can then reference a
# total unique index. The alternative, a `CONSTRAINT TRIGGER`, was rejected: the
# Ruby schema dumper does not emit triggers, so the invariant would exist in a
# migrated database and silently vanish from every database built by
# `db:schema:load` — including the test one.
#
# The second generated column is what makes the invariant state-dependent
# without a conditional foreign key, which PostgreSQL does not have. An ACTIVE
# Team must point at an ACTIVE OWNER membership; a Team in
# OWNERSHIP_RECOVERY_REQUIRED must point at the SUSPENDED one (doc 04 §3.2), and
# that is a total function of `status`.
class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.text :name, null: false
      t.text :slug, null: false
      t.column :owner_user_id, :"char(26)", null: false
      t.text :status, null: false, default: "ACTIVE"

      t.virtual :owner_role, type: :text, as: "'OWNER'::text", stored: true
      t.virtual :owner_membership_status, type: :text, stored: true,
        as: "CASE WHEN status = 'OWNERSHIP_RECOVERY_REQUIRED' THEN 'SUSPENDED'::text ELSE 'ACTIVE'::text END"

      t.timestamptz :deleted_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # RESTRICT rather than CASCADE: a Team is not a property of its owner's row,
    # and deleting the user out from under it would destroy the tenant. Account
    # deletion is a status transition (`DELETED_PENDING`), never a `DELETE`.
    add_foreign_key :teams, :users, column: :owner_user_id, on_delete: :restrict

    # AC7 — unique among Teams that are not deleted. Partial, unlike the address
    # of a User: a slug is a name in a URL, not an identity, and doc 09 §19 makes
    # it human and mutable. A deleted Team must not hold its name forever.
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :teams, :slug, unique: true, where: "deleted_at IS NULL",
      name: "index_teams_unique_slug_when_not_deleted"

    add_index :teams, :owner_user_id

    add_check_constraint :teams,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "teams_id_is_ulid"

    add_check_constraint :teams,
      "owner_user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "teams_owner_user_id_is_ulid"

    add_check_constraint :teams,
      "btrim(name) <> '' AND length(name) <= 120",
      name: "teams_name_present"

    # The shape a slug may take, enforced where it is stored rather than only
    # where it is generated: a slug written by an import or a console is still a
    # segment of a URL.
    add_check_constraint :teams,
      "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' AND length(slug) BETWEEN 2 AND 63",
      name: "teams_slug_format"

    # Two states in this Story. `OWNERSHIP_RECOVERY_REQUIRED` is entered when the
    # OWNER is suspended (doc 04 §3.2); leaving it is M11-04's administrative
    # recovery. Adding a state later is an ordinary expand migration, which is
    # why this is `text` + CHECK and not a PostgreSQL ENUM.
    add_check_constraint :teams,
      "status IN ('ACTIVE', 'OWNERSHIP_RECOVERY_REQUIRED')",
      name: "teams_status_is_known"
  end
end
