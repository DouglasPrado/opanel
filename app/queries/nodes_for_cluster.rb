# Read model: all Nodes for a Cluster with derived status and staleness.
#
# Returns nodes with their latest observation, computing the derived status
# (which is the observation status when fresh, but "stale" when observation_at
# is older than FRESH_OBSERVATION_SECONDS). This is the query the UI uses to
# display the node list.
#
# ## Tenancy is enforced through Cluster loading
#
# The Cluster is loaded through TenantScope before this Query is called, so
# the query can trust that only accessible nodes are shown.
class NodesForCluster
  Result = Data.define(:id, :swarm_node_id, :hostname, :role, :availability, :status,
    :advertise_address, :private_address, :public_address, :last_seen_at, :stale,
    :latest_observation) do
    def stale? = stale
  end

  def self.call(cluster:) = new(cluster: cluster).call

  def initialize(cluster:)
    @cluster = cluster
  end

  def call
    @cluster.nodes.kept.order(:id).map { |node| result_for(node) }
  end

  private

  # Builds the result for one node with its latest observation.
  def result_for(node)
    observation = node.latest_observation
    stale = node.observation_stale?

    Result.new(
      id: node.external_id,
      swarm_node_id: node.swarm_node_id,
      hostname: node.hostname,
      role: node.role,
      availability: node.availability,
      status: observation&.status || node.status,
      advertise_address: node.advertise_address,
      private_address: node.private_address,
      public_address: node.public_address,
      last_seen_at: node.last_seen_at,
      stale: stale,
      latest_observation: observation
    )
  end
end
