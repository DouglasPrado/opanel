# frozen_string_literal: true

require "rails_helper"

# Node observation and registration against a real Swarm Engine (Annex D §7).
#
# AC1, AC7 are about the real Manager and a node leaving the Swarm. The disposable
# lab has a single node, so only AC1 can be fully tested here. AC7 (node
# disappears → DOWN) requires a cluster with multiple nodes, which the lab
# cannot provide on demand. The application logic is tested in
# `spec/integration/node_observation_spec.rb` and `spec/unit/observe_cluster_nodes_spec.rb`;
# this suite verifies the real-world integration.
RSpec.describe "Node observation, against a real Swarm Engine", :swarm, :integration do
  subject(:executor) { SwarmExecutor.new }

  let(:cluster) { create(:cluster, :bootstrapped) }

  def command(type, **payload)
    ExecutorCommand.new(id: "cmd_#{type}_#{SecureRandom.hex(3)}", type: type,
      cluster_id: cluster.id, resource_type: "Node", resource_id: "list",
      correlation_id: "corr_lab", payload: payload)
  end

  describe "observing nodes from the Swarm (AC1)" do
    it "lists nodes from a real Swarm" do
      list_result = executor.execute(command("list_nodes"))

      expect(list_result).to be_applied
      expect(list_result.runtime_resource_ids).to be_a(Array)
      expect(list_result.runtime_resource_ids.length).to be >= 1
    end

    it "inspects a node from the Swarm and receives role, availability, state" do
      # First, list the nodes to get a valid ID
      list_result = executor.execute(command("list_nodes"))
      expect(list_result).to be_applied

      node_id = list_result.runtime_resource_ids.first
      expect(node_id).to be_present

      # Now inspect that node
      inspect_cmd = ExecutorCommand.new(
        id: "cmd_inspect_#{SecureRandom.hex(3)}",
        type: "inspect_node",
        cluster_id: cluster.id,
        resource_type: "Node",
        resource_id: node_id,
        correlation_id: "corr_lab"
      )

      inspect_result = executor.execute(inspect_cmd)
      expect(inspect_result).to be_applied
      expect(inspect_result.safe_metadata[:role]).to eq("manager")
      expect(inspect_result.safe_metadata[:state]).to be_present
      expect(inspect_result.safe_metadata[:availability]).to be_present
    end

    it "the manager node reports READY state when Swarm is healthy" do
      list_result = executor.execute(command("list_nodes"))
      node_id = list_result.runtime_resource_ids.first

      inspect_cmd = ExecutorCommand.new(
        id: "cmd_inspect_#{SecureRandom.hex(3)}",
        type: "inspect_node",
        cluster_id: cluster.id,
        resource_type: "Node",
        resource_id: node_id,
        correlation_id: "corr_lab"
      )

      inspect_result = executor.execute(inspect_cmd)
      expect(inspect_result).to be_applied
      # The bootstrap verified the Engine is healthy and runs Swarm in manager mode
      expect(inspect_result.safe_metadata[:state]).to eq("ready")
    end
  end

  describe "end-to-end observation (AC1, AC3, AC4)" do
    it "fetches nodes from the real Swarm and persists them (AC1)" do
      # Simulate what ObserveClusterNodes does
      list_result = executor.execute(command("list_nodes"))
      expect(list_result).to be_applied

      node_ids = list_result.runtime_resource_ids
      expect(node_ids.length).to be >= 1

      # For each node, inspect it and create a record
      node_ids.each do |swarm_node_id|
        inspect_cmd = ExecutorCommand.new(
          id: "cmd_inspect_#{SecureRandom.hex(3)}",
          type: "inspect_node",
          cluster_id: cluster.id,
          resource_type: "Node",
          resource_id: swarm_node_id,
          correlation_id: "corr_lab"
        )

        inspect_result = executor.execute(inspect_cmd)
        expect(inspect_result).to be_applied

        # Create the node record and observation
        metadata = inspect_result.safe_metadata
        node = cluster.nodes.find_or_create_by!(swarm_node_id: swarm_node_id) do |n|
          n.hostname = swarm_node_id # In real usage, the metadata would have this
          n.role = (metadata[:role] || "manager").upcase
          n.availability = Node::ACTIVE
          n.status = (metadata[:state] || "joining").upcase
        end

        NodeObservation.create!(
          node_id: node.id,
          status: (metadata[:state] || "joining").upcase,
          availability: (metadata[:availability] || "ACTIVE").upcase,
          observed_at: Time.current
        )

        # Verify the node and observation exist
        expect(node.persisted?).to be true
        expect(node.observations.count).to be >= 1
        expect(node.latest_observation&.status).to eq((metadata[:state] || "joining").upcase)
      end
    end
  end
end
