# frozen_string_literal: true

require "rails_helper"

RSpec.describe Node, type: :model do
  describe "status derivation" do
    it "returns JOINING by default when no observation exists" do
      node = create(:node, status: Node::JOINING)
      expect(node.status).to eq(Node::JOINING)
    end

    it "reflects latest observation status when fresh" do
      node = create(:node, status: Node::JOINING, last_seen_at: Time.current)
      create(:node_observation, node: node, status: Node::READY, observed_at: Time.current)

      node.reload
      expect(node.status).to eq(Node::JOINING)  # node.status is desired state until updated by job
    end

    it "can transition between valid states" do
      node = create(:node, status: Node::JOINING)
      expect(node.ready?).to be false
      expect(node.joining?).to be true

      node.update!(status: Node::READY)
      expect(node.ready?).to be true
    end
  end

  describe "staleness detection" do
    it "is stale when observation is older than FRESH_OBSERVATION_SECONDS" do
      node = create(:node)
      create(:node_observation, node: node,
        observed_at: (Node::FRESH_OBSERVATION_SECONDS + 60).seconds.ago)
      expect(node.observation_stale?).to be true
    end

    it "is not stale when observation is recent" do
      node = create(:node)
      create(:node_observation, node: node, observed_at: 10.seconds.ago)
      expect(node.observation_stale?).to be false
    end

    it "is stale when never observed (no observations exist)" do
      node = create(:node)
      expect(node.observation_stale?).to be true
    end

    it "uses current time for staleness check by default" do
      node = create(:node)
      create(:node_observation, node: node, observed_at: 5.seconds.ago)
      travel_to(Time.current + 70.seconds) do
        expect(node.observation_stale?).to be true
      end
    end

    it "accepts a custom now time for staleness check" do
      node = create(:node, last_seen_at: 30.seconds.ago)
      now = Time.current + 80.seconds
      expect(node.observation_stale?(now)).to be true
    end
  end

  describe "role predicates" do
    it "identifies manager nodes correctly" do
      node = create(:node, role: Node::MANAGER)
      expect(node.manager?).to be true
      expect(node.worker?).to be false
    end

    it "identifies worker nodes correctly" do
      node = create(:node, role: Node::WORKER)
      expect(node.manager?).to be false
      expect(node.worker?).to be true
    end
  end

  describe "availability predicates" do
    it "identifies active nodes correctly" do
      node = create(:node, availability: Node::ACTIVE)
      expect(node.active?).to be true
      expect(node.paused?).to be false
      expect(node.draining?).to be false
    end

    it "identifies paused nodes correctly" do
      node = create(:node, availability: Node::PAUSE)
      expect(node.active?).to be false
      expect(node.paused?).to be true
      expect(node.draining?).to be false
    end

    it "identifies draining nodes correctly" do
      node = create(:node, availability: Node::DRAIN)
      expect(node.active?).to be false
      expect(node.paused?).to be false
      expect(node.draining?).to be true
    end
  end

  describe "latest_observation" do
    it "returns the most recent observation" do
      node = create(:node)
      old_obs = create(:node_observation, node: node, observed_at: 60.seconds.ago)
      new_obs = create(:node_observation, node: node, observed_at: Time.current)

      expect(node.latest_observation).to eq(new_obs)
      expect(node.latest_observation).not_to eq(old_obs)
    end

    it "returns nil when no observations exist" do
      node = create(:node)
      expect(node.latest_observation).to be_nil
    end
  end

  describe "validations" do
    it "requires swarm_node_id" do
      node = build(:node, swarm_node_id: nil)
      expect(node).not_to be_valid
      expect(node.errors[:swarm_node_id]).to be_present
    end

    it "requires hostname" do
      node = build(:node, hostname: nil)
      expect(node).not_to be_valid
      expect(node.errors[:hostname]).to be_present
    end

    it "requires valid role" do
      node = build(:node, role: "INVALID")
      expect(node).not_to be_valid
      expect(node.errors[:role]).to be_present
    end

    it "requires valid availability" do
      node = build(:node, availability: "INVALID")
      expect(node).not_to be_valid
      expect(node.errors[:availability]).to be_present
    end

    it "requires valid status" do
      node = build(:node, status: "INVALID")
      expect(node).not_to be_valid
      expect(node.errors[:status]).to be_present
    end
  end

  describe "scopes" do
    it "kept scope excludes deleted nodes" do
      cluster = create(:cluster)
      kept_node = create(:node, cluster: cluster, deleted_at: nil)
      deleted_node = create(:node, cluster: cluster, deleted_at: Time.current)

      expect(Node.kept).to include(kept_node)
      expect(Node.kept).not_to include(deleted_node)
    end

    it "accessible_to scope filters by user team membership" do
      owner_user = create(:user)
      team1 = create(:team, owner_user_id: owner_user.id)
      team2 = create(:team)

      accessing_user = create(:user)
      create(:team_member, :admin, team: team1, user: accessing_user)

      cluster1 = create(:cluster, team: team1)
      cluster2 = create(:cluster, team: team2)
      node1 = create(:node, cluster: cluster1)
      node2 = create(:node, cluster: cluster2)

      accessible = Node.accessible_to(accessing_user)
      expect(accessible).to include(node1)
      expect(accessible).not_to include(node2)
    end
  end
end
