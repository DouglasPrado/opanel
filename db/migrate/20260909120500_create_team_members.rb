# migration-phase: expand
#
# Membership of a Team, and the four database constraints that make ownership a
# fact rather than an application convention (doc 04 §3.2 and §16.1, doc 09 §18).
#
# The invariant is stated once, here, in three pieces that only work together:
#
#   1. `index_team_members_on_team_id_and_user_id` — one membership per person
#      per Team.
#   2. `index_team_members_one_active_owner_per_team` — a partial unique that
#      makes a second OWNER+ACTIVE impossible. This is what refuses the loser of
#      a race, at the btree, without either transaction having to read first.
#   3. `fk_teams_active_owner_membership` — a composite foreign key that makes an
#      OWNER *exist*. A unique index can forbid a duplicate; only a key can
#      require a row. It is what refuses an active Team with no OWNER, refuses
#      demoting or removing the OWNER in place, and refuses suspending the OWNER
#      without moving the Team into OWNERSHIP_RECOVERY_REQUIRED.
#
# `index_team_members_owner_reference` is that key's target. It is redundant as a
# uniqueness rule — (1) already implies it — and exists because PostgreSQL
# requires a *total* unique index on the referenced columns and rejects a partial
# one. Its cost is one more small index on a table with a few rows per Team.
#
# DEFERRABLE INITIALLY DEFERRED, for two reasons. The keys are circular — a Team
# references its owner's membership, a membership references its Team — so
# creating both in one transaction is only possible if one side is checked at
# COMMIT. And suspending an OWNER has to write two rows that are momentarily
# inconsistent with each other; deferring means the transaction is judged on
# where it ends, never on the order the two statements happened to run in.
class CreateTeamMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :team_members, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :team_id, :"char(26)", null: false
      t.column :user_id, :"char(26)", null: false
      t.text :role, null: false
      t.text :status, null: false
      # Who sent the invitation. Nullable because the first membership of a Team
      # is not invited by anybody — it is the founder's own (doc 09 §3.2).
      t.column :invited_by, :"char(26)"
      # Null while INVITED, set when the membership becomes real.
      t.timestamptz :joined_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # RESTRICT everywhere. A membership is the audit trail of who had access to a
    # Team, and doc 04 §5.2 keeps it after REMOVED; a cascade would erase exactly
    # the history that survives removal.
    add_foreign_key :team_members, :teams, column: :team_id, on_delete: :restrict
    add_foreign_key :team_members, :users, column: :user_id, on_delete: :restrict
    add_foreign_key :team_members, :users, column: :invited_by, on_delete: :restrict

    # migration-index-review: new empty table — the builds are instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :team_members, [ :team_id, :user_id ], unique: true

    # AC2. Partial, so it constrains only the rows that matter: any number of
    # ADMINs, any number of former OWNERs already REMOVED, and at most one
    # *living* OWNER — whether they currently grant access or not.
    #
    # The status set is ACTIVE **and** SUSPENDED on purpose, and constraining
    # only ACTIVE would leave a hole rather than a narrower rule. While a Team
    # sits in OWNERSHIP_RECOVERY_REQUIRED its `owner_membership_status` is
    # SUSPENDED, so `fk_teams_active_owner_membership` is satisfied by the
    # suspended ex-OWNER and the ACTIVE slot would be free: a second row could be
    # born OWNER+ACTIVE, giving the Team a live owner who is not
    # `teams.owner_user_id`, precisely while it waits for the administrative
    # recovery of M11-04. Covering both statuses means the suspended OWNER keeps
    # occupying the slot, so nobody can take the Team during recovery.
    #
    # M11-03's transfer still works: within one transaction it demotes the
    # current OWNER and only then promotes the new one, and by that statement the
    # slot is free.
    add_index :team_members, :team_id, unique: true,
      where: "role = 'OWNER' AND status IN ('ACTIVE', 'SUSPENDED')",
      name: "index_team_members_one_active_owner_per_team"

    # The target of the composite key. See the class comment.
    add_index :team_members, [ :team_id, :user_id, :role, :status ], unique: true,
      name: "index_team_members_owner_reference"

    # Every request that resolves "which Teams may this user see" reads this,
    # and it is the read that makes a suspension take effect on the next request.
    add_index :team_members, [ :user_id, :status ]

    add_check_constraint :team_members,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "team_members_id_is_ulid"

    add_check_constraint :team_members,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "team_members_team_id_is_ulid"

    add_check_constraint :team_members,
      "user_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "team_members_user_id_is_ulid"

    add_check_constraint :team_members,
      "invited_by IS NULL OR invited_by ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "team_members_invited_by_is_ulid"

    # doc 04 §5.1 also lists BILLING as optional for a later phase. It is not in
    # this Story's scope, and adding it is an expand migration on this CHECK.
    add_check_constraint :team_members,
      "role IN ('OWNER', 'ADMIN', 'DEVELOPER', 'VIEWER')",
      name: "team_members_role_is_known"

    add_check_constraint :team_members,
      "status IN ('INVITED', 'ACTIVE', 'SUSPENDED', 'REMOVED')",
      name: "team_members_status_is_known"

    # A membership that was ever accepted knows when. Only INVITED may lack it,
    # so `joined_at` cannot quietly be null on an ACTIVE member and turn every
    # later "member since" into a guess.
    add_check_constraint :team_members,
      "status = 'INVITED' OR joined_at IS NOT NULL",
      name: "team_members_joined_at_present_once_accepted"

    # AC3, AC4 and the database half of AC5. Named explicitly because the tests
    # assert on this name: an error that only says "a foreign key" would pass
    # against the wrong constraint.
    add_foreign_key :teams, :team_members,
      column: [ :id, :owner_user_id, :owner_role, :owner_membership_status ],
      primary_key: [ :team_id, :user_id, :role, :status ],
      name: "fk_teams_active_owner_membership",
      deferrable: :deferred
  end
end
