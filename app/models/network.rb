# An overlay network for an Environment, isolated from other Environments (doc 08 §4.1).
#
# ## Desired vs Actual State
#
# Like Cluster, Environment and Service, Network tracks desired_revision and
# applied_revision. The reconciler advances applied_revision only after re-inspecting
# the Docker Swarm and confirming the network exists with the correct ownership
# labels (doc 07 §11.3, AC3, AC11).
#
# ## Deterministic naming
#
# The network name is derived deterministically from opaque IDs, so renaming the
# Environment or Project does not change the Docker resource name. The name is
# computed by Opanel::Ownership.technical_name_for(environment) (doc 08 §5, M01-16 AC3).
#
# ## Isolation
#
# One network per Environment. Services in the same Environment can communicate via
# the network; Services in different Environments cannot (unless explicitly attached,
# which is out of scope for this Story). This is enforced by the reconciler, not
# assumed (AC8).
#
class Network < ApplicationRecord
  include UlidPrimaryKey

  # Statuses (doc 09 §5.2, doc 07 §17).
  PROVISIONING = "PROVISIONING"
  READY = "READY"
  DEGRADED = "DEGRADED"
  DELETING = "DELETING"
  STATUSES = [ PROVISIONING, READY, DEGRADED, DELETING ].freeze

  # Drivers (doc 08 §4.1).
  OVERLAY = "overlay"
  DRIVERS = [ OVERLAY ].freeze

  belongs_to :environment
  belongs_to :cluster
  belongs_to :team

  has_many :reconciliation_runs, as: :resource, dependent: :destroy

  validates :name, presence: true
  validates :driver, inclusion: { in: DRIVERS }
  validates :status, inclusion: { in: STATUSES }
  validates :swarm_network_id, format: { with: /\A[a-z0-9]+\z/ }, allow_nil: true

  scope :kept, -> { where(deleted_at: nil) }
  scope :active, -> { kept.where(status: READY) }

  # Reuse the Environment's technical_name, which delegates to Ownership.
  def technical_name
    Opanel::Ownership.technical_name_for(environment)
  end

  # Whether the network can transition to the target status (state machine guard).
  # Networks in DELETING cannot transition further.
  def can_transition_to?(target)
    return false if status == DELETING
    # For now, allow any status transition (full flexibility during reconciliation).
    # Future: may add a more restrictive state machine.
    STATUSES.include?(target)
  end

  # Whether this network has converged: applied_revision matches desired_revision
  # and status is READY (not PROVISIONING/DEGRADED/DELETING).
  def converged?
    applied_revision == desired_revision && ready?
  end

  # Status predicates (convenience).
  def provisioning? = status == PROVISIONING
  def ready? = status == READY
  def degraded? = status == DEGRADED
  def deleting? = status == DELETING
end
