# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObserveClusterNodesJob, type: :integration do
  include ActiveJob::TestHelper

  describe "job class" do
    it "descends from ApplicationJob" do
      expect(ObserveClusterNodesJob).to be < ApplicationJob
    end

    it "can be loaded and enqueued" do
      previous = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      begin
        expect {
          ObserveClusterNodesJob.perform_later
        }.to have_enqueued_job(ObserveClusterNodesJob)
      ensure
        ActiveJob::Base.queue_adapter = previous
      end
    end
  end
end

RSpec.describe ObserveClusterNodes, type: :model do
  let(:cluster) { create(:cluster, :bootstrapped) }
  let(:executor) { instance_double(SwarmExecutor) }

  before do
    allow(Current).to receive(:request_id).and_return("req-123")
  end

  describe "successful observation" do
    it "creates nodes from list_nodes and inspect_node results" do
      node1_id = "node1abc123def456ghi"
      node2_id = "node2xyz789uvw456mno"

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

      allow(executor).to receive(:execute)
        .and_return(list_result, inspect1_result, inspect2_result)

      result = ObserveClusterNodes.call(cluster: cluster, executor: executor)

      expect(result).to be_success
      expect(cluster.nodes.count).to eq(2)
      expect(cluster.nodes.find_by(swarm_node_id: node1_id).role).to eq("MANAGER")
      expect(cluster.nodes.find_by(swarm_node_id: node2_id).role).to eq("WORKER")
    end

    it "creates NodeObservation records with timestamps" do
      node_id = "node1abc123def456ghi"

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node_id ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1", availability: "ACTIVE" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      node = cluster.nodes.find_by(swarm_node_id: node_id)
      expect(node.observations.count).to eq(1)
      observation = node.observations.first
      expect(observation.status).to eq("READY")
      expect(observation.observed_at).to be_within(1.second).of(Time.current)
    end

    it "updates existing node with latest observation" do
      node_id = "node1abc123def456ghi"
      existing_node = create(:node, cluster: cluster, swarm_node_id: node_id,
        status: Node::JOINING)

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node_id ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1", availability: "ACTIVE" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      existing_node.reload
      expect(existing_node.status).to eq(Node::READY)
      expect(existing_node.observations.count).to eq(1)
    end

    it "denormalizes last_seen_at on node after observation" do
      node_id = "node1abc123def456ghi"

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node_id ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      before_time = Time.current
      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      node = cluster.nodes.find_by(swarm_node_id: node_id)
      expect(node.last_seen_at).to be_within(1.second).of(before_time)
    end

    it "is idempotent — two calls produce same state" do
      node_id = "node1abc123def456ghi"

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node_id ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)
      count_after_first = cluster.nodes.count

      # Call again with fresh mocks
      allow(executor).to receive(:execute).and_return(list_result, inspect_result)
      ObserveClusterNodes.call(cluster: cluster, executor: executor)
      count_after_second = cluster.nodes.count

      expect(count_after_first).to eq(count_after_second)
    end
  end

  describe "failure handling" do
    it "marks cluster as UNREACHABLE when list_nodes fails (AC6)" do
      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(false)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:error_code).and_return("ENGINE_UNAVAILABLE")

      allow(executor).to receive(:execute).and_return(list_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      cluster.reload
      expect(cluster.status).to eq(Cluster::UNREACHABLE)
      expect(cluster.unreachable_reason).to eq("ENGINE_UNAVAILABLE")
      expect(cluster.observed_at).to be_within(1.second).of(Time.current)
    end

    it "preserves last observation when Docker fails (AC6)" do
      old_time = 1.hour.ago
      node = create(:node, cluster: cluster, status: Node::READY,
        last_seen_at: old_time)
      create(:node_observation, node: node, status: Node::READY)

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(false)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:error_code).and_return("ENGINE_UNAVAILABLE")

      allow(executor).to receive(:execute).and_return(list_result)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)

      node.reload
      expect(node.observations.count).to eq(1)  # No new observation created
      expect(node.last_seen_at).to eq(old_time)  # Old timestamp still there
    end

    it "continues with other nodes if one inspect fails" do
      node1_id = "node1abc123def456ghi"
      node2_id = "node2xyz789uvw456mno"

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node1_id, node2_id ] })

      inspect1_result = instance_double(ExecutionResult)
      allow(inspect1_result).to receive(:applied?).and_return(false)
      allow(inspect1_result).to receive(:noop?).and_return(false)

      inspect2_result = instance_double(ExecutionResult)
      allow(inspect2_result).to receive(:applied?).and_return(true)
      allow(inspect2_result).to receive(:noop?).and_return(false)
      allow(inspect2_result).to receive(:safe_metadata).and_return(
        { role: "WORKER", state: "READY", hostname: "worker-1" }
      )

      allow(executor).to receive(:execute)
        .and_return(list_result, inspect1_result, inspect2_result)

      result = ObserveClusterNodes.call(cluster: cluster, executor: executor)

      # One node was created despite the other failing
      expect(cluster.nodes.count).to eq(1)
      expect(cluster.nodes.first.swarm_node_id).to eq(node2_id)
      expect(result.value[:observed_count]).to eq(1)
    end
  end

  describe "logging" do
    it "logs successful observation with cluster and node counts" do
      node_id = "node1abc123def456ghi"

      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ node_id ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "MANAGER", state: "READY", hostname: "manager-1" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      # Allow any info calls but expect cluster.nodes.observed at least once
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info)
        .with(hash_including(event: "cluster.nodes.observed")).at_least(:once)

      ObserveClusterNodes.call(cluster: cluster, executor: executor)
    end
  end
end
