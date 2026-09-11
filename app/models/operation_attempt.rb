# Each OperationAttempt is immutable and preserves the timeline of retries (doc 09 §9.2).
#
# A new OperationAttempt is created for each execution attempt; previous attempts
# are never overwritten. This allows audit and diagnosis of the retry history.
#
class OperationAttempt < ApplicationRecord
  include UlidPrimaryKey

  belongs_to :operation

  validates :operation_id, presence: true
  validates :attempt_number, presence: true, numericality: { only_integer: true }
  validates :started_at, presence: true
  validates :outcome, presence: true

  scope :ordered, -> { order(:attempt_number) }

  # Once persisted, an OperationAttempt is immutable (no updates after creation).
  # This is not enforced at the database level but is a contract.
end
