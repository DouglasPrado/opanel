# migration-phase: expand
#
# `citext` on its own, before the first table that needs it.
#
# The address of a user is a case-insensitive identity — `Person@Example.test`
# and `person@example.test` are the same account — and doc 09 §3.1 makes that a
# property of the column rather than of whichever code path happens to normalize
# before writing. A `lower(email)` unique index would express the same rule while
# leaving every query free to forget it.
#
# Kept in its own migration because it is a database-level privilege: `CREATE
# EXTENSION` needs a role that may install one, and an installation whose
# PostgreSQL user cannot will fail here, with one line naming the extension,
# rather than half way through creating the identity tables.
class EnableCitext < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext"
  end
end
