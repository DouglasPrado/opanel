# Whether a Cluster can be operated, and what it cannot do (doc 06 §14.1).
#
# ## Operational is not the same question as highly available
#
# doc 06 §14.1 opens by refusing "Ready / Not Ready": *"Um cluster single-node
# pode estar operacional sem estar altamente disponível"*. So this answers two
# things separately. `operational` is whether workloads can run at all;
# `highly_available` is whether losing a node would keep them running, and on a
# single-node cluster it is `false` — which is correct, expected, and must not be
# hidden behind a green tick.
#
# The full readiness matrix of doc 06 §14.1 — quorum, ingress, registry, build
# capacity, overlay reachability — is `M08-12`, when there is more than one node
# to have a topology at all. This is the minimal version the Story asks for.
#
# ## Every answer carries when it was observed
#
# A readiness view that prints "Operational YES" from a reading taken an hour ago
# is worse than one that prints nothing: it is the false confidence doc 10 §25's
# stale state exists to prevent. `observed_at` and `stale` travel with the answer,
# never as something the caller may forget to ask for.
class ClusterReadinessView
  Check = Data.define(:name, :status, :detail)

  Result = Data.define(:id, :name, :slug, :status, :swarm_id, :advertise_address,
    :observed_at, :stale, :unreachable_reason, :operational, :highly_available,
    :node_count, :checks, :permissions) do
    def stale? = stale
    def operational? = operational
    def highly_available? = highly_available
  end

  Permissions = Data.define(:refresh, :bootstrap)

  # doc 06 §14.1's vocabulary, kept to the rows a single-node M01 cluster can
  # actually answer.
  HEALTHY = "HEALTHY"
  DEGRADED = "DEGRADED"
  UNKNOWN = "UNKNOWN"

  def self.call(actor:, cluster:, node_count: nil)
    new(actor: actor, cluster: cluster, node_count: node_count).call
  end

  def initialize(actor:, cluster:, node_count: nil)
    @actor = actor
    @cluster = cluster
    @node_count = node_count
  end

  def call
    policy = ClusterPolicy.new(actor, cluster)

    Result.new(
      id: cluster.external_id,
      name: cluster.name,
      slug: cluster.slug,
      status: cluster.status,
      swarm_id: cluster.swarm_id,
      advertise_address: cluster.advertise_address,
      observed_at: cluster.observed_at,
      stale: cluster.observation_stale?,
      unreachable_reason: cluster.unreachable_reason,
      operational: operational?,
      # A single manager is a single point of failure by definition. Reported as
      # `false` rather than omitted: an operator who is not told is an operator
      # who assumes.
      highly_available: false,
      node_count: @node_count,
      checks: checks,
      permissions: Permissions.new(refresh: policy.refresh?, bootstrap: policy.bootstrap?)
    )
  end

  private

  attr_reader :actor, :cluster

  # Operational only on a **fresh** READY reading. A stale one is not evidence
  # that the cluster is working now, and this is the one place that decision is
  # made so no screen can make it differently.
  def operational? = cluster.ready? && !cluster.observation_stale?

  def checks
    [
      swarm_check,
      manager_check,
      observation_check
    ]
  end

  def swarm_check
    if cluster.bootstrapped?
      Check.new(name: "swarm", status: HEALTHY, detail: cluster.swarm_id)
    else
      Check.new(name: "swarm", status: UNKNOWN, detail: "no Swarm has been initialised yet")
    end
  end

  def manager_check
    case cluster.status
    when Cluster::READY then Check.new(name: "manager", status: HEALTHY, detail: "1 manager, no quorum yet")
    when Cluster::UNREACHABLE then Check.new(name: "manager", status: UNKNOWN,
      detail: cluster.unreachable_reason || "the daemon did not answer")
    else Check.new(name: "manager", status: DEGRADED, detail: cluster.unreachable_reason || cluster.status)
    end
  end

  def observation_check
    if cluster.observed_at.nil?
      Check.new(name: "observation", status: UNKNOWN, detail: "never observed")
    elsif cluster.observation_stale?
      Check.new(name: "observation", status: DEGRADED,
        detail: "last observed #{cluster.observed_at.iso8601}")
    else
      Check.new(name: "observation", status: HEALTHY, detail: cluster.observed_at.iso8601)
    end
  end
end
