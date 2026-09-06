# migration-phase: expand
#
# Technical infrastructure table. It carries no Opanel domain concept: it is the
# named, monotonic marker that infrastructure code writes to prove an effect
# happened exactly once — used by the example job's idempotency test (M00-03) and
# by the concurrency harness (M00-07).
#
# Identifier strategy: ADR-0002 (ULID, char(26)) is still `Proposed` and governs
# domain entities exposed through the API, MCP and Swarm labels. This table is
# neither exposed nor a domain entity, so it keeps the Rails bigint key. The first
# domain table waits for the ADR to be accepted (SC-08, M01-01).
class CreateInfrastructureCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_checkpoints do |t|
      t.string :name, null: false
      t.bigint :counter, null: false, default: 0

      t.timestamps
    end

    # migration-index-review: new empty table, so the index is built instantly;
    # CONCURRENTLY is unnecessary and would forbid running inside the transaction.
    add_index :infrastructure_checkpoints, :name, unique: true

    # Uniqueness and the non-negative invariant live in PostgreSQL, not only in the
    # model: a second writer that bypasses Active Record must still be rejected.
    add_check_constraint :infrastructure_checkpoints,
      "counter >= 0",
      name: "infrastructure_checkpoints_counter_non_negative"
  end
end
