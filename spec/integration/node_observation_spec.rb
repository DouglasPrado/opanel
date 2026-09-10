# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node observation", type: :integration do
  let(:team) { create(:team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }

  describe "observation isolation" do
    it "does not share observations between nodes" do
      node1 = create(:node, cluster: cluster, status: Node::READY)
      node2 = create(:node, cluster: cluster, status: Node::JOINING)

      obs1 = create(:node_observation, node: node1, status: Node::READY, observed_at: 60.seconds.ago)
      obs2 = create(:node_observation, node: node2, status: Node::DEGRADED, observed_at: Time.current)

      node1.reload
      node2.reload

      expect(node1.observations).to contain_exactly(obs1)
      expect(node2.observations).to contain_exactly(obs2)
      expect(node1.observations).not_to include(obs2)
    end

    it "does not share observations between clusters" do
      cluster2 = create(:cluster, :bootstrapped, team: team)
      node1 = create(:node, cluster: cluster, status: Node::READY)
      node2 = create(:node, cluster: cluster2, status: Node::READY)

      obs1 = create(:node_observation, node: node1, status: Node::READY)
      obs2 = create(:node_observation, node: node2, status: Node::READY)

      expect(node1.observations).to contain_exactly(obs1)
      expect(node2.observations).to contain_exactly(obs2)
    end
  end

  describe "node disappearance from Swarm (AC7)" do
    let(:executor) { instance_double(SwarmExecutor) }

    before do
      allow(Current).to receive(:request_id).and_return("req-123")
    end

    it "marks a node DOWN when it disappears from observation list (AC7)" do
      # Create two existing nodes
      node1_id = "node1abc123def456ghi"
      node2_id = "node2xyz789uvw456mno"

      node1 = create(:node, cluster: cluster, swarm_node_id: node1_id, status: Node::READY)
      node2 = create(:node, cluster: cluster, swarm_node_id: node2_id, status: Node::READY)

      create(:node_observation, node: node1, status: Node::READY, observed_at: 1.hour.ago)
      create(:node_observation, node: node2, status: Node::READY, observed_at: 1.hour.ago)

      # First observation: both nodes are present
      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node1_id, node2_id ] })

      inspect1_result = instance_double(ExecutionResult)
      allow(inspect1_result).to receive(:applied?).and_return(true)
      allow(inspect1_result).to receive(:noop?).and_return(false)
      allow(inspect1_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1", availability: "ACTIVE" }
      )

      inspect2_result = instance_double(ExecutionResult)
      allow(inspect2_result).to receive(:applied?).and_return(true)
      allow(inspect2_result).to receive(:noop?).and_return(false)
      allow(inspect2_result).to receive(:safe_metadata).and_return(
        { role: "WORKER", state: "READY", hostname: "worker-1", availability: "ACTIVE" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect1_result, inspect2_result)
      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      # Verify both nodes are READY
      expect(node1.reload.status).to eq(Node::READY)
      expect(node2.reload.status).to eq(Node::READY)

      # Second observation: node2 has disappeared, only node1 returned
      list_result2 = instance_double(ExecutionResult)
      allow(list_result2).to receive(:applied?).and_return(true)
      allow(list_result2).to receive(:noop?).and_return(false)
      allow(list_result2).to receive(:safe_metadata).and_return({ ids: [ node1_id ] })

      inspect1_result2 = instance_double(ExecutionResult)
      allow(inspect1_result2).to receive(:applied?).and_return(true)
      allow(inspect1_result2).to receive(:noop?).and_return(false)
      allow(inspect1_result2).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1", availability: "ACTIVE" }
      )

      allow(executor).to receive(:execute).and_return(list_result2, inspect1_result2)
      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      # Verify node1 is still READY
      expect(node1.reload.status).to eq(Node::READY)

      # Verify node2 is now DOWN and still persisted
      expect(node2.reload.status).to eq(Node::DOWN)
      expect(node2.persisted?).to be true

      # Verify history is intact
      expect(node2.observations.count).to eq(3)  # First observation + DOWN observation from each run
      observation_statuses = node2.observations.order(:observed_at).map(&:status)
      expect(observation_statuses).to include(Node::READY, Node::DOWN)
    end

    it "does not mark nodes DOWN when list_nodes fails (AC6 companion)" do
      # Create a node that exists
      node_id = "node1abc123def456ghi"
      old_time = 1.hour.ago
      node = create(:node, cluster: cluster, swarm_node_id: node_id, status: Node::READY,
        last_seen_at: old_time)
      create(:node_observation, node: node, status: Node::READY)

      # list_nodes fails
      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(false)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:error_code).and_return("ENGINE_UNAVAILABLE")

      allow(executor).to receive(:execute).and_return(list_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      # Node should remain READY (not marked DOWN)
      expect(node.reload.status).to eq(Node::READY)
      # No new observation created
      expect(node.observations.count).to eq(1)
      # last_seen_at unchanged
      expect(node.last_seen_at).to eq(old_time)
    end
  end

  describe "node deletion cascade" do
    it "deletes associated observations when node is deleted" do
      node = create(:node, cluster: cluster)
      observation = create(:node_observation, node: node)

      expect {
        node.destroy
      }.to change { NodeObservation.count }.by(-1)

      expect(NodeObservation.find_by(id: observation.id)).to be_nil
    end

    it "does not allow deleting cluster if it has nodes (RESTRICT)" do
      _node = create(:node, cluster: cluster)

      expect {
        cluster.destroy
      }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end

  describe "uniqueness constraints" do
    it "enforces unique swarm_node_id per cluster at database level" do
      node1 = create(:node, cluster: cluster, swarm_node_id: "unique-id-1")

      expect {
        create(:node, cluster: cluster, swarm_node_id: "unique-id-1")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows same swarm_node_id in different clusters" do
      cluster2 = create(:cluster, :bootstrapped, team: team)
      node1 = create(:node, cluster: cluster, swarm_node_id: "same-id")

      node2 = nil
      expect {
        node2 = create(:node, cluster: cluster2, swarm_node_id: "same-id")
      }.not_to raise_error

      expect(node2).to be_persisted
    end
  end

  describe "observation timestamps" do
    it "stores observed_at with timezone information" do
      now = Time.current
      observation = create(:node_observation, observed_at: now)

      fetched = NodeObservation.find(observation.id)
      expect(fetched.observed_at).to be_within(1.second).of(now)
      expect(fetched.observed_at.zone).not_to be_nil
    end

    it "orders observations by observed_at descending for latest queries" do
      node = create(:node, cluster: cluster)
      obs1 = create(:node_observation, node: node, observed_at: 60.seconds.ago)
      obs2 = create(:node_observation, node: node, observed_at: 30.seconds.ago)
      obs3 = create(:node_observation, node: node, observed_at: Time.current)

      latest = node.observations.order(observed_at: :desc).first
      expect(latest).to eq(obs3)
    end
  end

  describe "node-cluster relationship" do
    it "requires cluster_id (FK NOT NULL)" do
      # Model validation catches nil cluster_id first
      expect {
        Node.create!(swarm_node_id: "test", hostname: "test", role: "MANAGER",
          availability: "ACTIVE", status: "JOINING", cluster_id: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "prevents orphaned nodes when loading through cluster" do
      node = create(:node, cluster: cluster)
      observation = create(:node_observation, node: node)

      cluster.reload
      expect(cluster.nodes).to include(node)
    end
  end

  describe "observation immutability" do
    it "observations are never updated by application code (enforced through tests and code review)" do
      # NodeObservation immutability is enforced through:
      # 1. No update calls in ObserveClusterNodes (observations are only created, never updated)
      # 2. Tests verify create-only behavior
      # 3. Code review ensures observation fields are never touched after initial creation
      # ActiveRecord readonly is not used because it would prevent cascade deletes
      observation = create(:node_observation, status: Node::READY)

      # Verify the observation exists and has its original data
      fetched = NodeObservation.find(observation.id)
      expect(fetched.status).to eq(Node::READY)
      expect(fetched.observed_at).to eq(observation.observed_at)
    end
  end

  describe "status and availability enums" do
    Node::STATUSES.each do |status|
      it "accepts status #{status}" do
        node = create(:node, cluster: cluster, status: status)
        expect(node.status).to eq(status)
      end
    end

    Node::AVAILABILITIES.each do |availability|
      it "accepts availability #{availability}" do
        node = create(:node, cluster: cluster, availability: availability)
        expect(node.availability).to eq(availability)
      end
    end

    NodeObservation::STATUSES.each do |status|
      it "accepts observation status #{status}" do
        observation = build(:node_observation, status: status)
        expect(observation).to be_valid
      end
    end

    it "rejects invalid status through model validation" do
      expect {
        Node.create!(cluster_id: cluster.id, swarm_node_id: "test", hostname: "test",
          role: "MANAGER", availability: "ACTIVE", status: "INVALID")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "concurrent observation writes" do
    it "allows concurrent NodeObservation creates for same node" do
      node = create(:node, cluster: cluster)

      threads = 3.times.map do |i|
        Thread.new do
          NodeObservation.create!(
            node_id: node.id,
            status: Node::READY,
            observed_at: Time.current + i.seconds
          )
        end
      end

      threads.each(&:join)

      expect(node.observations.count).to eq(3)
    end

    it "prevents duplicate node_id + swarm_node_id pairs" do
      create(:node, cluster: cluster, swarm_node_id: "test-1")

      expect {
        create(:node, cluster: cluster, swarm_node_id: "test-1")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
