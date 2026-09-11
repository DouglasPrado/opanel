require "rails_helper"

RSpec.describe "Network Diff Calculation", type: :unit do
  # The diff is a pure function: compute_diff(desired_state, actual_state) → diff_class
  # AC1: diff must have no side effects; it is computed as a value, not an action.
  # AC6: unowned networks block reconciliation, never adopted.
  # AC4: idempotence: running reconcile twice produces NOOP the second time.

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) do
    create(:environment, project: project, cluster: cluster, team: team)
  end

  describe "compute_diff" do
    it "returns NOOP when desired and actual states are equivalent" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::READY, desired_revision: 1,
        applied_revision: 1, swarm_network_id: "aabbccdd112233",
        name: environment.technical_name)

      # Mock the ownership check to return true for this test
      allow(Opanel::Ownership).to receive(:managed_by_platform?).and_return(true)

      actual = {
        "ID" => "aabbccdd112233",
        "Version" => { "Index" => 1 },
        "CreatedAt" => "2026-09-11T00:00:00Z",
        "UpdatedAt" => "2026-09-11T00:00:00Z",
        "Spec" => {
          "Name" => environment.technical_name,
          "Labels" => { "com.opanel.managed" => "true" },
          "Driver" => "overlay"
        }
      }

      diff = Opanel::NetworkDiff.compute(desired: network, actual: actual)

      expect(diff.diff_class).to eq(ReconciliationRun::NOOP)
    end

    it "returns CREATE when the network does not exist" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::PROVISIONING, desired_revision: 1,
        applied_revision: nil, swarm_network_id: nil)

      diff = Opanel::NetworkDiff.compute(desired: network, actual: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::CREATE)
    end

    it "returns BLOCKED when network exists without platform ownership" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::PROVISIONING, desired_revision: 1)

      # A network without the com.opanel.managed label
      actual = {
        "ID" => "net_456",
        "Spec" => {
          "Name" => "some-other-network",
          "Labels" => {},
          "Driver" => "overlay"
        }
      }

      diff = Opanel::NetworkDiff.compute(desired: network, actual: actual)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to include("is not managed by the platform")
    end

    it "returns BLOCKED when a network with a conflicting name exists" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::PROVISIONING, desired_revision: 1)

      # A network with the expected name but wrong ownership
      actual = {
        "ID" => "net_789",
        "Spec" => {
          "Name" => network.technical_name,
          "Labels" => { "com.other" => "label" },  # No com.opanel.managed
          "Driver" => "overlay"
        }
      }

      diff = Opanel::NetworkDiff.compute(desired: network, actual: actual)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
    end

    it "returns NOOP when network exists with platform ownership and same revision" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::READY, desired_revision: 2,
        applied_revision: 2, swarm_network_id: "aabbccdd445566",
        name: environment.technical_name)

      # Mock the ownership check to return true for this test
      allow(Opanel::Ownership).to receive(:managed_by_platform?).and_return(true)

      actual = {
        "ID" => "aabbccdd445566",
        "Spec" => {
          "Name" => environment.technical_name,
          "Labels" => { "com.opanel.managed" => "true" },
          "Driver" => "overlay"
        }
      }

      diff = Opanel::NetworkDiff.compute(desired: network, actual: actual)

      expect(diff.diff_class).to eq(ReconciliationRun::NOOP)
    end
  end

  describe "diff idempotence" do
    it "produces the same diff class when called twice with same inputs" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::PROVISIONING, desired_revision: 1)

      diff1 = Opanel::NetworkDiff.compute(desired: network, actual: nil)
      diff2 = Opanel::NetworkDiff.compute(desired: network, actual: nil)

      expect(diff1.diff_class).to eq(diff2.diff_class)
      expect(diff1.diff_class).to eq(ReconciliationRun::CREATE)
    end
  end

  describe "diff with no side effects" do
    it "does not modify the network record" do
      network = create(:network, environment: environment, cluster: cluster,
        team: team, status: Network::PROVISIONING, desired_revision: 1)

      original_status = network.status
      original_swarm_id = network.swarm_network_id

      Opanel::NetworkDiff.compute(desired: network, actual: nil)

      network.reload

      expect(network.status).to eq(original_status)
      expect(network.swarm_network_id).to eq(original_swarm_id)
    end
  end
end
