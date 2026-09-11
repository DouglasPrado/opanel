# Authorization for a Cluster (doc 04 §6.2, §7.1; UC-003).
#
# ## Bootstrapping needs two things, and the second is not a Team role
#
# The Story is explicit: *"bootstrap exige `INSTANCE_ADMIN`; leitura exige
# membership no Team"*. Those are conditions in different tables, and both hold.
#
# The Team half is doc 04 §6.2's "Adicionar/remover Cluster", which is OWNER and
# ADMIN. The installation half is doc 04 §7.1, which keeps administering the
# installation separate from owning a tenant — an INSTANCE_ADMIN is not
# automatically anything inside a Team, and a Team's OWNER is not automatically an
# administrator of the installation.
#
# Requiring both is deny-by-default applied to a decision that spans two
# authorities. It also matches how a real installation looks: the person who
# bootstraps it is seated as OWNER of the first Team by `BootstrapInstallation`
# and holds `INSTANCE_ADMIN` from the same command, so the ordinary path is
# unaffected and the unusual ones are refused.
#
# ## Why the instance check is inside `decide`
#
# `Opanel::Authorization.authorize!` calls `decide`, never the predicates. A
# subclass that checked the instance role in `bootstrap?` alone would be bypassed
# by every caller — which is all of them. `extra_denial_reason` is the hook
# `ApplicationPolicy` exposes for exactly this, and it produces a truthful reason
# in the audit trail rather than borrowing `out_of_scope`.
class ClusterPolicy < ApplicationPolicy
  PERMISSIONS = {
    # doc 04 §6.2, row "Adicionar/remover Cluster": OWNER and ADMIN. Read from
    # `TeamPolicy` rather than restated, so there is one place where the matrix
    # lives.
    bootstrap: TeamPolicy::PERMISSIONS.fetch(:manage_clusters),

    # Everyone with an active membership. A Cluster nobody may look at is a
    # Cluster nobody can operate around.
    view: TeamPolicy::PERMISSIONS.fetch(:view),

    # Refreshing writes only *observed* state — never user intent — so it carries
    # the read roles rather than the management ones. A VIEWER looking at a stale
    # reading should be able to ask for a current one; that is the whole point of
    # a derived status.
    refresh: TeamPolicy::PERMISSIONS.fetch(:view),

    # Reading nodes is observation data (actual state), not a write. Uses view roles.
    nodes: TeamPolicy::PERMISSIONS.fetch(:view)
  }.freeze

  # Actions that additionally require an instance role, and which one.
  INSTANCE_ROLE_FOR = { bootstrap: InstanceRole::ADMIN }.freeze

  def self.permissions = PERMISSIONS

  # Written out rather than generated: AF-07 greps for `def <action>?`, and a
  # generated predicate leaves the fitness function passing because it found
  # nothing to check.
  def bootstrap? = decide(:bootstrap).allowed?
  def view? = decide(:view).allowed?
  def refresh? = decide(:refresh).allowed?
  def nodes? = decide(:nodes).allowed?

  private

  # Constructed with a Cluster when one exists, and with the Team it will belong
  # to when the decision is whether one may exist at all — `teamId` is NOT NULL
  # (SC-12), so there is always a Team to scope to.
  def team
    return resource if resource.is_a?(Team)
    return resource.team if resource.is_a?(Cluster)

    nil
  end

  def extra_denial_reason(action, _membership)
    required = INSTANCE_ROLE_FOR[action.to_sym]
    return nil if required.nil?
    return nil if holds_instance_role?(required)

    :instance_role_required
  end

  # Asked of the rows rather than of anything cached: revoking an instance role
  # takes effect on the very next decision, with nothing to invalidate — the same
  # property membership suspension has.
  def holds_instance_role?(role)
    return false if actor.nil?

    InstanceRole.active.where(user_id: actor.id, role: role).exists?
  end
end
