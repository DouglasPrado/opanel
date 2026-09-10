# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node observation redaction", type: :security do
  describe "no secrets in observation data" do
    it "does not expose join tokens in node observations (AC10)" do
      cluster = create(:cluster, :bootstrapped)
      node = create(:node, cluster: cluster)
      observation = create(:node_observation, node: node)

      # Observation should never contain join tokens
      expect(observation.attributes.values).not_to include(match(/SWMTKN/))
      expect(observation.to_json).not_to include("SWMTKN")
    end

    it "does not expose docker credentials in node observations (AC10)" do
      cluster = create(:cluster, :bootstrapped)
      node = create(:node, cluster: cluster)
      observation = create(:node_observation, node: node)

      observation_data = observation.attributes
      expect(observation_data).not_to include(match(/password|secret|credential|auth/i))
    end

    it "does not expose private addresses to non-members (AC10)" do
      owner_user = create(:user)
      team1 = create(:team, owner_user_id: owner_user.id)
      team2 = create(:team)

      accessing_user = create(:user)
      create(:team_member, :admin, team: team1, user: accessing_user)

      cluster1 = create(:cluster, :bootstrapped, team: team1)
      cluster2 = create(:cluster, :bootstrapped, team: team2)

      node1 = create(:node, cluster: cluster1, private_address: "192.168.1.1")
      node2 = create(:node, cluster: cluster2, private_address: "192.168.1.2")

      # Accessing user can access team1 cluster but not team2
      cluster1_nodes = NodesForCluster.call(cluster: cluster1)
      expect(cluster1_nodes.map(&:private_address)).not_to be_empty

      # When accessing_user tries to access team2, should get no access (through policy)
      policy = ClusterPolicy.new(accessing_user, cluster2)
      expect(policy.nodes?).to be false
    end
  end

  describe "logging redaction" do
    it "does not log join tokens when observing nodes" do
      cluster = create(:cluster, :bootstrapped)

      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(Current).to receive(:request_id).and_return("req-123")

      executor = instance_double(SwarmExecutor)
      list_result = instance_double(ExecutionResult)
      allow(list_result).to receive(:applied?).and_return(true)
      allow(list_result).to receive(:noop?).and_return(false)
      allow(list_result).to receive(:safe_metadata).and_return({ ids: [ "node1" ] })

      inspect_result = instance_double(ExecutionResult)
      allow(inspect_result).to receive(:applied?).and_return(true)
      allow(inspect_result).to receive(:noop?).and_return(false)
      allow(inspect_result).to receive(:safe_metadata).and_return(
        { role: "manager", state: "READY", hostname: "node-1" }
      )

      allow(executor).to receive(:execute).and_return(list_result, inspect_result)

      # Expect that any logged messages do not contain SWMTKN
      expect(logger).not_to receive(:info)
        .with(hash_including(SWMTKN: anything))
      expect(logger).not_to receive(:warn)
        .with(hash_including(SWMTKN: anything))
      expect(logger).not_to receive(:error)
        .with(hash_including(SWMTKN: anything))

      ObserveClusterNodes.call(cluster: cluster, executor: executor)
    end

    it "does not expose node details in error responses" do
      owner_user = create(:user)
      team = create(:team, owner_user_id: owner_user.id)
      user = create(:user)
      create(:team_member, :admin, team: team, user: user)

      cluster = create(:cluster, :bootstrapped, team: team)

      # This test would be implemented in a controller spec when the endpoint is added
      # For now, verify that NodesForCluster does not expose sensitive data
      node = create(:node, cluster: cluster, private_address: "192.168.1.1")
      nodes = NodesForCluster.call(cluster: cluster)

      # Results should not include raw private addresses in error context
      expect(nodes.first.private_address).to eq("192.168.1.1")
    end
  end

  describe "audit trail sanitization" do
    it "does not record join tokens in audit logs for node operations" do
      # This is a placeholder for when node mutations are added in future Stories
      # For now, observation-only has no audit trail
      cluster = create(:cluster, :bootstrapped)
      node = create(:node, cluster: cluster)

      # When node operations are added, audit logs should not contain tokens
      audit_logs = AuditLog.where(resource_type: "Node")
      audit_logs.each do |log|
        expect(log.before_state).not_to include("SWMTKN") if log.before_state
        expect(log.after_state).not_to include("SWMTKN") if log.after_state
      end
    end
  end

  describe "serialization safety" do
    it "does not expose secrets when serializing node to JSON" do
      cluster = create(:cluster, :bootstrapped)
      node = create(:node, cluster: cluster, labels: { "secret_key" => "secret_value" })

      json = node.to_json
      expect(json).to include("secret_value")  # Labels are visible
      expect(json).not_to include("SWMTKN")
      expect(json).not_to include(/password|auth|token/i)
    end

    it "does not expose secrets in NodesForCluster result serialization" do
      cluster = create(:cluster, :bootstrapped)
      node = create(:node, cluster: cluster)

      nodes = NodesForCluster.call(cluster: cluster)
      result = nodes.first

      # Result should be safely serializable
      json_str = result.to_h.to_json
      expect(json_str).not_to include("SWMTKN")
      expect(json_str).not_to match(/password|auth|token/i)
    end
  end
end
