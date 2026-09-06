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

  # Converges on the row instead of duplicating it. The unique index is what makes
  # this safe under concurrency — the validation only turns the common case into a
  # cheaper query, and losing that race is expected, not exceptional.
  def self.converge!(name)
    find_by(name: name) || create!(name: name)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    find_by(name: name) || raise(error)
  end

  # Counts an execution without reading the current value first, so two workers
  # cannot lose each other's increment.
  def count_execution!
    self.class.where(id: id).update_all("counter = counter + 1")
  end
end
