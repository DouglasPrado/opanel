# A named, monotonic marker written by infrastructure code.
#
# This is not an Opanel domain entity — M00 implements no domain. It exists so
# that infrastructure behaviour can be proven against real PostgreSQL: that a
# unique constraint rejects a duplicate, that a counter survives a rollback, that
# an idempotent job effect is not applied twice (M00-03), and that a lost update
# is visible without a lock and prevented with one (M00-07).
class InfrastructureCheckpoint < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :counter, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
