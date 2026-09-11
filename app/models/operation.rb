# An Operation is a durable, stateful representation of infrastructure work (doc 07 §5, doc 09 §9.1).
#
# Every mutation that affects runtime is represented as an Operation in the same
# PostgreSQL transaction as the Desired State change and OutboxEvent. The Operation
# records intent, status, attempt history and error codes without exposing secrets
# or stack traces.
#
# State machine (doc 07 §5.2):
#   PENDING → QUEUED → RUNNING → (WAITING_RUNTIME → VERIFYING) → SUCCEEDED | RETRYABLE → QUEUED
#   Terminal: FAILED, CANCELED, SUPERSEDED, TIMED_OUT
#
class Operation < ApplicationRecord
  include UlidPrimaryKey

  # Raised when a state transition is invalid.
  class InvalidTransition < StandardError
    attr_reader :from_status, :to_status

    def initialize(from_status, to_status)
      @from_status = from_status
      @to_status = to_status
      super("Invalid transition from #{from_status} to #{to_status}")
    end
  end

  # Rails' Single Table Inheritance would interpret the `type` column as the STI
  # discriminator; we disable it to use `type` as the operation kind field per doc 07 §5.1.
  self.inheritance_column = nil

  # State machine: doc 07 §5.2.
  PENDING = "PENDING"
  QUEUED = "QUEUED"
  RUNNING = "RUNNING"
  WAITING_RUNTIME = "WAITING_RUNTIME"
  VERIFYING = "VERIFYING"
  SUCCEEDED = "SUCCEEDED"
  RETRYABLE = "RETRYABLE"
  FAILED = "FAILED"
  CANCELED = "CANCELED"
  SUPERSEDED = "SUPERSEDED"
  TIMED_OUT = "TIMED_OUT"

  STATUSES = [
    PENDING, QUEUED, RUNNING, WAITING_RUNTIME, VERIFYING,
    SUCCEEDED, RETRYABLE, FAILED, CANCELED, SUPERSEDED, TIMED_OUT
  ].freeze

  TERMINAL_STATUSES = [ SUCCEEDED, FAILED, CANCELED, SUPERSEDED, TIMED_OUT ].freeze

  # State transitions (doc 07 §5.2, enforced by model).
  # Supersession marks a queued operation as obsolete when a newer revision arrives.
  TRANSITIONS = {
    PENDING => [ QUEUED, SUPERSEDED, CANCELED ],
    QUEUED => [ RUNNING, SUPERSEDED, CANCELED ],
    RUNNING => [ WAITING_RUNTIME, SUCCEEDED, RETRYABLE, FAILED, TIMED_OUT ],
    WAITING_RUNTIME => [ VERIFYING, FAILED, TIMED_OUT ],
    VERIFYING => [ SUCCEEDED, RETRYABLE, FAILED ],
    SUCCEEDED => [],
    RETRYABLE => [ QUEUED ],
    FAILED => [],
    CANCELED => [],
    SUPERSEDED => [],
    TIMED_OUT => []
  }.freeze

  # Error classes from doc 07 §5.3.
  ERROR_CLASSES = %i[validation conflict transient runtime_rejection timeout unknown_outcome].freeze

  belongs_to :team
  has_many :attempts, class_name: "OperationAttempt", foreign_key: :operation_id, dependent: :destroy

  # Validations.
  validates :team_id, presence: true
  validates :resource_type, presence: true
  validates :resource_id, presence: true
  validates :type, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :desired_revision, presence: true, numericality: { only_integer: true }
  validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :payload, presence: true
  validates :error_code, inclusion: { in: ERROR_CLASSES.map(&:to_s) }, allow_nil: true

  scope :pending, -> { where(status: PENDING) }
  scope :queued, -> { where(status: QUEUED) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }

  # Transition validation: ensure the requested transition is allowed.
  def can_transition_to?(new_status)
    return false unless STATUSES.include?(new_status)
    return false if status == new_status

    TRANSITIONS.fetch(status, []).include?(new_status)
  end

  def transition_to!(new_status)
    raise InvalidTransition.new(status, new_status) unless can_transition_to?(new_status)

    update!(status: new_status)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def succeeded?
    status == SUCCEEDED
  end

  def failed?
    status == FAILED
  end

  def superseded?
    status == SUPERSEDED
  end

  # Mark this Operation as superseded by a newer revision. Newer Operations should reconcile directly.
  def mark_superseded!
    transition_to!(SUPERSEDED) unless terminal?
  end

  # Mark this Operation as stalled (watchdog observation, not a status change).
  # stalled_at and stalled_reason are attributes that record the watchdog's finding.
  # An Operation with stalled_at != nil is observed to have no progress (doc 07 §22, Annex B §6).
  def mark_stalled!(reason)
    update!(stalled_at: Time.current.utc, stalled_reason: reason)
  end

  # Check if this Operation is marked as stalled.
  def stalled?
    stalled_at.present?
  end
end
