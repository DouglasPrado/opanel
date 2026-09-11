# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Node cross-team access", type: :policy do
  describe "nodes are not visible across team boundaries" do
    it "allows viewing nodes only within team membership (AC9)" do
      team1 = create(:team)
      team2 = create(:team)
      user = create(:user)

      # User is member of team1 only (other than the owner created by factory)
      create(:team_member, team: team1, user: user, role: "ADMIN", status: "ACTIVE")

      cluster1 = create(:cluster, :bootstrapped, team: team1)
      cluster2 = create(:cluster, :bootstrapped, team: team2)

      node1 = create(:node, cluster: cluster1)
      node2 = create(:node, cluster: cluster2)

      # User can see nodes in cluster1
      accessible = Node.accessible_to(user)
      expect(accessible).to include(node1)
      expect(accessible).not_to include(node2)
    end

    it "denies access to another team's nodes even with same ID" do
      # Each team factory creates its own owner; just use the owner created by factory
      team1 = create(:team)
      team2 = create(:team)
      user1 = team1.owner
      user2 = team2.owner

      cluster1 = create(:cluster, :bootstrapped, team: team1)
      cluster2 = create(:cluster, :bootstrapped, team: team2)

      node1 = create(:node, cluster: cluster1)
      node2 = create(:node, cluster: cluster2)

      # user1 cannot see team2's nodes
      user1_accessible = Node.accessible_to(user1)
      expect(user1_accessible).to include(node1)
      expect(user1_accessible).not_to include(node2)

      # user2 cannot see team1's nodes
      user2_accessible = Node.accessible_to(user2)
      expect(user2_accessible).to include(node2)
      expect(user2_accessible).not_to include(node1)
    end

    it "respects suspended team membership" do
      team = create(:team)
      user = create(:user)
      member = create(:team_member, team: team, user: user, role: "ADMIN", status: "ACTIVE")

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster)

      # User can see node while active
      expect(Node.accessible_to(user)).to include(node)

      # Suspend the membership
      member.update!(status: "SUSPENDED")

      # User can no longer see node
      expect(Node.accessible_to(user)).not_to include(node)
    end

    it "respects deleted team" do
      team = create(:team)
      user = team.owner

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster)

      expect(Node.accessible_to(user)).to include(node)

      # Delete the team (soft delete)
      team.update!(deleted_at: Time.current)

      # User can no longer see node
      expect(Node.accessible_to(user)).not_to include(node)
    end

    it "respects deleted node" do
      team = create(:team)
      user = team.owner

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster, deleted_at: nil)

      expect(Node.accessible_to(user)).to include(node)

      node.update!(deleted_at: Time.current)

      expect(Node.accessible_to(user)).not_to include(node)
    end
  end

  describe "nodes are readable by team members" do
    it "allows VIEW role to read nodes" do
      team = create(:team)
      user = create(:user)
      create(:team_member, :viewer, team: team, user: user)

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster)

      policy = ClusterPolicy.new(user, cluster)
      expect(policy.nodes?).to be true
    end

    it "allows ADMIN role to read nodes" do
      team = create(:team)
      user = create(:user)
      create(:team_member, :admin, team: team, user: user)

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster)

      policy = ClusterPolicy.new(user, cluster)
      expect(policy.nodes?).to be true
    end

    it "allows OWNER role to read nodes" do
      team = create(:team)
      user = team.owner

      cluster = create(:cluster, :bootstrapped, team: team)
      node = create(:node, cluster: cluster)

      policy = ClusterPolicy.new(user, cluster)
      expect(policy.nodes?).to be true
    end
  end
end
