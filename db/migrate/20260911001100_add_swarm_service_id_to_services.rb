# M01-18. The Service reconciler observes a Swarm Service and has nowhere to
# record which one it is.
#
# `services` already carries `desired_revision` and `applied_revision` from
# M01-12; what is missing is the runtime id, so this is one column and
# expand-only: additive, nullable, no backfill, no rename, no drop. Old code
# ignores it, new code writes it after a re-inspection confirms the resource,
# and the rollback is `remove_column`.
#
# Shape copied from `networks.swarm_network_id` deliberately — one shape for
# "the runtime id of a resource this platform owns", including the format check.
# Nullable because it is an *observation*: a DRAFT Service has none, and the
# reconciler never guesses one.
#
# The partial unique index states the invariant a duplicate-create bug would
# otherwise leave silent: two Service rows may never claim the same Swarm
# Service (M01-18 AC7).
class AddSwarmServiceIdToServices < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :services, :swarm_service_id, :string

    # migration-index-review: partial unique index over a column that is NULL on
    # every existing row, built concurrently; no table rewrite and no lock.
    add_index :services,
      :swarm_service_id,
      name: "index_services_unique_swarm_service_id",
      unique: true,
      where: "swarm_service_id IS NOT NULL AND deleted_at IS NULL",
      algorithm: :concurrently

    add_check_constraint :services,
      "swarm_service_id IS NULL OR swarm_service_id ~ '^[a-z0-9]+$'",
      name: "services_swarm_service_id_valid",
      validate: false
  end
end
