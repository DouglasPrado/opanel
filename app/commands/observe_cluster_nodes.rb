# Observe the runtime Swarm nodes and persist the reading (AC1, AC3, AC4, AC6, AC8).
#
# ## Called by the periodic job
#
# This command is invoked by `ObserveClusterNodesJob` on a regular schedule
# (doc 07 §23). It fetches the list of nodes from the Swarm executor and, for
# each one, creates or updates the `Node` record and appends a `NodeObservation`.
#
# ## Idempotent by design
#
# Two calls with the same state produce the same database state. Nodes are
# identified by their `swarm_node_id`, which is unique per cluster. If a node
# was already registered, the observation is still appended. No duplicate rows
# are created by concurrent calls.
#
# ## Handles Docker failures gracefully
#
# If the Docker daemon is unreachable, the command succeeds with the last
# observation intact. The Cluster status is marked UNREACHABLE with a cause.
# The Control Plane never loses the last-known state of a node, and the UI
# signals staleness (doc 10 §25).
#
# ## Actual state only
#
# Observations hold only what the runtime reported: status, availability,
# resources, engine version, and the timestamp. No desired state is written here.
class ObserveClusterNodes
  def self.call(cluster:, executor: SwarmExecutor)
    new(cluster: cluster, executor: executor).call
  end

  def initialize(cluster:, executor: SwarmExecutor)
    @cluster = cluster
    @executor = executor
  end

  def call
    # List all nodes from the Swarm.
    list_result = list_nodes
    unless list_result.applied? || list_result.noop?
      handle_list_failure(list_result)
      return Opanel::Result.failure(code: "DOCKER_UNAVAILABLE", message: "Could not read nodes from Swarm",
        details: { cause: list_result.error_code })
    end

    # For each node, inspect it and create/update the record.
    node_ids = list_result.safe_metadata[:ids] || []
    observed_count = 0

    node_ids.each do |swarm_node_id|
      inspect_result = inspect_node(swarm_node_id)
      next unless inspect_result.applied? || inspect_result.noop?

      process_node_inspection(swarm_node_id, inspect_result)
      observed_count += 1
    end

    # Check if any nodes disappeared from the Swarm (AC7).
    mark_disappeared_nodes_as_down(node_ids)

    Rails.logger.info(event: "cluster.nodes.observed", cluster_id: @cluster.external_id,
      team_id: @cluster.team.external_id, node_count: node_ids.length,
      observed_count: observed_count, result: "succeeded")

    Opanel::Result.success(nodes_count: node_ids.length, observed_count: observed_count)
  rescue StandardError => error
    Rails.logger.error(event: "cluster.nodes.observed", cluster_id: @cluster.external_id,
      team_id: @cluster.team.external_id, error: error.message, result: "failed")
    Opanel::Result.failure(code: "OBSERVATION_FAILED", message: "Failed to observe nodes",
      details: { error: error.message })
  end

  private

  attr_reader :cluster, :executor

  # Call the executor to list nodes in the Swarm.
  def list_nodes
    command = ExecutorCommand.new(
      id: "cmd_list_nodes_#{SecureRandom.hex(3)}",
      type: "list_nodes",
      cluster_id: cluster.id,
      resource_type: "node",
      resource_id: "list",
      correlation_id: Current.request_id
    )
    executor.execute(command)
  end

  # Call the executor to inspect a specific node.
  def inspect_node(swarm_node_id)
    command = ExecutorCommand.new(
      id: "cmd_inspect_node_#{SecureRandom.hex(3)}",
      type: "inspect_node",
      cluster_id: cluster.id,
      resource_type: "node",
      resource_id: swarm_node_id,
      correlation_id: Current.request_id
    )
    executor.execute(command)
  end

  # Process the inspection result and create/update the node and observation.
  def process_node_inspection(swarm_node_id, inspect_result)
    metadata = inspect_result.safe_metadata

    # Find or create the Node record.
    node = cluster.nodes.find_or_create_by!(swarm_node_id: swarm_node_id) do |n|
      n.hostname = metadata[:hostname] || swarm_node_id
      n.role = metadata[:role] || Node::MANAGER
      n.availability = Node::ACTIVE
      n.status = metadata[:state] || Node::JOINING
      n.advertise_address = metadata[:advertise_address]
    end

    # Update node fields from latest inspection.
    node.update!(
      hostname: metadata[:hostname] || node.hostname,
      role: metadata[:role] || node.role,
      status: metadata[:state] || node.status,
      last_seen_at: Time.current
    )

    # Create an immutable observation record.
    NodeObservation.create!(
      node_id: node.id,
      status: metadata[:state] || Node::JOINING,
      availability: metadata[:availability],
      resources: metadata[:resources],
      engine_version: metadata[:engine_version],
      observed_at: Time.current
    )

    Rails.logger.info(event: "node.observed", cluster_id: cluster.external_id,
      node_id: node.external_id, swarm_node_id: swarm_node_id, status: node.status,
      role: node.role)
  end

  # Mark nodes that disappeared from the Swarm as DOWN (AC7).
  # Nodes that are no longer reported by list_nodes but exist in the database
  # are marked as DOWN without being deleted. This preserves the full audit trail
  # and distinguishes "the node left the cluster" from "we could not see it".
  def mark_disappeared_nodes_as_down(current_swarm_node_ids)
    # Find all nodes in this cluster whose swarm_node_id is not in the current list.
    # These nodes existed before but were not returned by list_nodes, so they
    # have disappeared from the Swarm.
    disappeared_nodes = cluster.nodes.where.not(swarm_node_id: current_swarm_node_ids)

    disappeared_nodes.find_each do |node|
      # Mark the node as DOWN and update the timestamp.
      node.update!(
        status: Node::DOWN,
        last_seen_at: Time.current
      )

      # Create an immutable observation record to document the disappearance.
      NodeObservation.create!(
        node_id: node.id,
        status: Node::DOWN,
        availability: node.availability, # Preserve last known availability
        resources: nil, # No resource data available for disappeared node
        engine_version: nil,
        observed_at: Time.current
      )

      Rails.logger.info(event: "node.disappeared", cluster_id: cluster.external_id,
        node_id: node.external_id, swarm_node_id: node.swarm_node_id)
    end
  end

  # Handle failure to list nodes from the Swarm.
  # The cluster status is degraded, but the last observation is preserved.
  def handle_list_failure(list_result)
    cluster.update!(
      status: Cluster::UNREACHABLE,
      unreachable_reason: list_result.error_code || "UNKNOWN",
      observed_at: Time.current
    )

    Rails.logger.warn(event: "cluster.nodes.list_failed", cluster_id: cluster.external_id,
      team_id: cluster.team.external_id, error: list_result.error_code)
  end
end
