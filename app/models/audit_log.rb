# The append-only record of a privileged action (doc 04 §10, doc 09 §15.1).
#
# Immutability is asserted in three places, and each one covers a different way of
# losing it: the model refuses `update` and `destroy`; the `revision = 1` CHECK
# means an UPDATE that touches the column fails in PostgreSQL; and a spec asserts
# that no application code performs either. See the migration for why a trigger —
# the obvious choice — was ruled out.
class AuditLog < ApplicationRecord
  include UlidPrimaryKey

  class Immutable < StandardError; end

  ACTOR_TYPES = %w[USER API_TOKEN SYSTEM RECOVERY].freeze
  RESULTS = %w[SUCCESS DENIED FAILED].freeze

  # Actions of this Milestone, named once so they cannot drift between the Command
  # that writes them and the query that reads them. Stable and namespaced: doc 09
  # §15.1 asks for names a trail can be filtered by years from now.
  ACTIONS = {
    installation_bootstrapped: "installation.bootstrapped",
    team_created: "team.created",
    team_member_suspended: "team.member.suspended",
    team_ownership_recovery_required: "team.ownership.recovery_required",
    user_registered: "user.registered",
    user_signed_in: "user.signed_in",
    user_sign_in_failed: "user.sign_in_failed",
    session_revoked: "session.revoked",
    instance_role_granted: "instance_role.granted",
    instance_role_revoked: "instance_role.revoked",
    authorization_denied: "authorization.denied",
    project_created: "project.created",
    project_updated: "project.updated",
    project_archived: "project.archived",
    environment_created: "environment.created",
    environment_updated: "environment.updated",
    network_created: "network.created",
    service_created: "service.created",
    service_updated: "service.updated",
    # M01-18. Applying a revision to the Swarm is a privileged action with no
    # human actor: the trail records SYSTEM, the Service, the Operation that
    # asked for it and the result, so a deploy is answerable without reproducing
    # it (AGENT_RULES, "Audit").
    service_deployed: "service.deployed",
    service_reconcile_blocked: "service.reconcile.blocked",
    cluster_bootstrapped: "cluster.bootstrapped",
    cluster_adopted: "cluster.adopted",
    cluster_bootstrap_failed: "cluster.bootstrap_failed"
  }.freeze

  # Events about the installation itself, which legitimately have no Team. Every
  # other action must carry one — the inverse rule the Story asks a test to guard.
  INSTANCE_ACTIONS = [
    ACTIONS[:installation_bootstrapped],
    ACTIONS[:user_registered],
    ACTIONS[:user_signed_in],
    ACTIONS[:user_sign_in_failed],
    ACTIONS[:session_revoked],
    ACTIONS[:instance_role_granted],
    ACTIONS[:instance_role_revoked],
    # A denial is recorded even when the Team could not be resolved — an actor
    # refused for having no membership may be asking about a resource whose
    # tenancy the decision never established. Refusing to record it because the
    # Team is unknown would drop exactly the denials worth keeping.
    ACTIONS[:authorization_denied]
  ].freeze

  validates :actor_type, inclusion: { in: ACTOR_TYPES }
  validates :result, inclusion: { in: RESULTS }
  validates :action, inclusion: { in: ACTIONS.values }
  validates :request_id, :correlation_id, :resource_type, presence: true
  validate :team_is_present_unless_instance_event

  scope :for_request, ->(request_id) { where(request_id: request_id).order(:created_at) }
  scope :for_resource, ->(type, id) {
    where(resource_type: type, resource_id: id).order(created_at: :desc)
  }

  # Append-only, in the model. Overriding rather than relying on a callback: a
  # callback can be skipped with `update_columns`, and while nothing stops that
  # reaching the database, it should not be reachable by writing ordinary Rails.
  def readonly? = persisted?

  def update(*) = raise(Immutable, "an audit record is append-only (doc 04 §10)")
  def update!(*) = raise(Immutable, "an audit record is append-only (doc 04 §10)")
  def destroy = raise(Immutable, "an audit record is append-only (doc 04 §10)")
  def destroy! = raise(Immutable, "an audit record is append-only (doc 04 §10)")

  def instance_event? = INSTANCE_ACTIONS.include?(action)

  private

  def team_is_present_unless_instance_event
    return if instance_event?
    return if team_id.present?

    errors.add(:team_id, "is required for #{action}, which is not an installation event")
  end
end
