# migration-phase: expand
#
# The Project — the logical product of a Team (doc 09 §5.1).
#
# The structural decision this table encodes is what it does **not** reference:
# there is no `cluster_id` here. doc 01 §5.1 and doc 09 §5.1 both say a Project is
# not a child of a Cluster; the Environment is what chooses where things run. A
# column pointing at infrastructure would make the wrong model true in the schema
# and everything above it would inherit the mistake.
#
# `default_environment_id` is the one forward reference, and it is deliberately
# **not** a foreign key yet: `environments` arrives with `M01-11`, which adds the
# key in its own expand migration. doc 09 §5.1 calls the field "referência de UX",
# so a Project whose default Environment was deleted must degrade to "no default",
# never fail to load. The CHECK below still refuses anything that is not a ULID —
# a dangling reference may be absent, not malformed.
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects, id: false do |t|
      t.column :id, :"char(26)", null: false, primary_key: true
      t.column :team_id, :"char(26)", null: false
      t.text :name, null: false
      t.text :slug, null: false
      t.text :description
      t.column :default_environment_id, :"char(26)"
      t.text :status, null: false, default: "ACTIVE"

      t.timestamptz :deleted_at
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
    end

    # RESTRICT, like `teams.owner_user_id`: a Project is not a property of a row
    # that can be deleted out from under it. Removing a Team is a status
    # transition and a retention policy (doc 09 §25), never a `DELETE` that takes
    # its Projects with it silently.
    add_foreign_key :projects, :teams, column: :team_id, on_delete: :restrict

    # AC2 — doc 09 §18, verbatim: `UNIQUE(teamId, slug) WHERE deletedAt IS NULL`.
    # Partial, and per Team: AC3 requires the same slug to be free in a different
    # Team, and a deleted Project must not hold a name in a URL forever.
    #
    # migration-index-review: new empty table — the build is instantaneous and
    # CONCURRENTLY would forbid the transaction.
    add_index :projects, %i[team_id slug], unique: true, where: "deleted_at IS NULL",
      name: "index_projects_unique_slug_per_team_when_not_deleted"

    # The listing of AC6. The cursor is the ULID, so the page is a keyset on
    # `(team_id, id)` and this index is what makes it a range scan rather than a
    # sort of the Team's whole set.
    #
    # migration-index-review: new empty table.
    add_index :projects, %i[team_id id], name: "index_projects_on_team_id_and_id"

    add_check_constraint :projects,
      "id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "projects_id_is_ulid"

    add_check_constraint :projects,
      "team_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "projects_team_id_is_ulid"

    # Absent is allowed; malformed is not. See the note on the column above.
    add_check_constraint :projects,
      "default_environment_id IS NULL OR default_environment_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'",
      name: "projects_default_environment_id_is_ulid"

    add_check_constraint :projects,
      "btrim(name) <> '' AND length(name) <= 120",
      name: "projects_name_present"

    # The same shape a Team slug takes, enforced where it is stored rather than
    # only where it is generated: a slug written by an import or a console is
    # still a segment of a URL.
    add_check_constraint :projects,
      "slug ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' AND length(slug) BETWEEN 2 AND 63",
      name: "projects_slug_format"

    # doc 09 §5.1. `DELETING` is declared here and unreachable from the
    # application in M01: the transition that enters it is `M02-09`, which
    # reconciles the runtime before the row becomes a tombstone. Declaring the
    # state now is what keeps that Story from needing a CHECK migration on a table
    # with rows in it.
    add_check_constraint :projects,
      "status IN ('ACTIVE', 'ARCHIVED', 'DELETING')",
      name: "projects_status_is_known"

    # A description is optional, but an unbounded text column reachable from a
    # form is a way to make a page slow for one Team only.
    add_check_constraint :projects,
      "description IS NULL OR length(description) <= 2000",
      name: "projects_description_length"
  end
end
