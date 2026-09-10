# Re-reads the runtime and records what it said (AC7, AC11).
#
# This is the half of "status is derived" that keeps being true after the
# bootstrap. `Cluster#status` is not a decision the Control Plane made once; it is
# the last observation, and this is what takes one.
#
# ## A daemon that will not answer is a reading, not an error
#
# doc 06 §14 and the Story's Observability Requirements agree: an unreachable
# daemon means the Cluster is `UNREACHABLE` **with a classified cause**, and the
# UI keeps showing the previous reading with its age (doc 10 §25's stale state).
# It does not mean the request failed — so this Command succeeds, and the Result
# carries a Cluster whose status says what is wrong.
#
# The one thing it refuses to do is claim health it did not observe.
class RefreshClusterStatus
  def self.call(actor:, cluster:, executor: SwarmBootstrap)
    new(actor: actor, cluster: cluster, executor: executor).call
  end

  def initialize(actor:, cluster:, executor: SwarmBootstrap)
    @actor = actor
    @cluster = cluster
    @executor = executor
  end

  def call
    # Same pattern as `BootstrapCluster`: the Policy is named and its predicate
    # called, so `grep refresh?` finds where this is decided.
    policy = ClusterPolicy.new(actor, cluster)
    unless policy.refresh?
      decision = policy.decide(:refresh)
      Opanel::Authorization.record(actor, decision)

      return Opanel::Result.failure(code: "NOT_FOUND", message: "That cluster could not be found.",
        details: {})
    end

    observation = observe

    # Outside any transaction, and there is none to be inside: this writes one
    # row and makes a network call before it. The call happens first.
    cluster.update!(
      status: observation.fetch(:status),
      unreachable_reason: observation[:reason],
      swarm_id: observation[:swarm_id] || cluster.swarm_id,
      observed_at: Time.current
    )

    Rails.logger.info(event: "cluster.observed", team_id: cluster.team.external_id,
      cluster_id: cluster.external_id, status: cluster.status,
      reason: cluster.unreachable_reason, result: "succeeded")

    Opanel::Result.success(cluster: cluster)
  end

  private

  attr_reader :actor, :cluster, :executor

  def observe
    engine = executor.info

    return { status: Cluster::UNREACHABLE, reason: "SWARM_INACTIVE" } unless engine.swarm_active?

    # A Cluster registered against one Swarm now reporting another means the
    # daemon was rebuilt underneath it. Saying "READY" about it would be the
    # Control Plane agreeing with a runtime it no longer knows.
    if cluster.swarm_id.present? && engine.swarm_id.present? && engine.swarm_id != cluster.swarm_id
      return { status: Cluster::DEGRADED, reason: "SWARM_ID_MISMATCH" }
    end

    unless engine.manager?
      return { status: Cluster::DEGRADED, reason: "NODE_IS_NOT_A_MANAGER", swarm_id: engine.swarm_id }
    end

    { status: Cluster::READY, reason: nil, swarm_id: engine.swarm_id }
  rescue SwarmBootstrap::EngineError => error
    # AC7 — the cause, never a generic timeout. `cause_code` is the vocabulary
    # `SwarmBootstrap` classifies into, so the UI and the trail agree on the word.
    { status: Cluster::UNREACHABLE, reason: error.cause_code }
  end
end
