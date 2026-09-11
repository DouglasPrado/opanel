# A record of a reconciliation run, persisted per execution (AC10, doc 07 §11.3).
#
# ## Purpose
#
# The reconciler computes a diff, applies actions and persists the result. This model
# holds that record — what resource was reconciled, what trigger caused it, what diff
# was computed, what actions were applied, and whether they succeeded. This makes a
# reconcile auditable without requiring reproduction (AC10).
#
# ## Triggers
#
# OPERATION: reconcile triggered by an Operation (e.g., CREATE_NETWORK)
# PERIODIC: reconcile triggered by the periodic sweep scheduler
# MANUAL: reconcile triggered by an admin action
#
# ## Result and diff_class
#
# If the reconciler detected no diff (NOOP) or completed the actions successfully,
# result is SUCCESS. If the diff was BLOCKED (e.g., network already exists without
# ownership), result is BLOCKED and error_reason holds the diagnosis. If an action
# failed, result is FAILED and error_reason describes it.
#
class ReconciliationRun < ApplicationRecord
  include UlidPrimaryKey

  # Results (AC10).
  SUCCESS = "SUCCESS"
  BLOCKED = "BLOCKED"
  FAILED = "FAILED"
  RESULTS = [ SUCCESS, BLOCKED, FAILED ].freeze

  # Diff classes (doc 07 §11.4).
  NOOP = "NOOP"
  CREATE = "CREATE"
  UPDATE_SAFE = "UPDATE_SAFE"
  ROLLOUT = "ROLLOUT"
  DELETE = "DELETE"
  BLOCKED_CLASS = "BLOCKED"
  DRIFT = "DRIFT"
  DIFF_CLASSES = [ NOOP, CREATE, UPDATE_SAFE, ROLLOUT, DELETE, BLOCKED_CLASS, DRIFT ].freeze

  # Triggers (AC10).
  OPERATION = "OPERATION"
  PERIODIC = "PERIODIC"
  MANUAL = "MANUAL"
  TRIGGERS = [ OPERATION, PERIODIC, MANUAL ].freeze

  belongs_to :resource, polymorphic: true
  belongs_to :team

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :diff_class, inclusion: { in: DIFF_CLASSES }
  validates :result, inclusion: { in: RESULTS }

  # Guard: failed runs must have an error_reason.
  validate :error_reason_required_if_not_success, unless: :new_record?

  def error_reason_required_if_not_success
    if result != SUCCESS && error_reason.blank?
      errors.add(:error_reason, "is required when result is not SUCCESS")
    end
  end

  scope :for_resource, ->(resource_type, resource_id) {
    where(resource_type: resource_type, resource_id: resource_id)
  }

  scope :recent, ->(days = 7) {
    where("created_at >= ?", days.days.ago)
  }
end
