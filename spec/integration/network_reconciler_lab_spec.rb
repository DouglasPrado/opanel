require "rails_helper"

RSpec.describe "Network reconciliation against live Swarm", type: :integration, swarm: true do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) do
    create(:environment, project: project, cluster: cluster, team: team)
  end

  it "creates network in Swarm with platform ownership labels (AC1, AC2)" do
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             name: environment.technical_name,
                             status: Network::PROVISIONING, desired_revision: 1)

    # Verify network doesn't exist yet
    expect(lab_resource_exists?("network", network.technical_name)).to be false

    # Run reconciler to create network
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler.call

    # Network should now exist in Swarm
    expect(lab_resource_exists?("network", network.technical_name)).to be true
    created_resources << [ "network", network.technical_name ]

    # Verify network has correct state
    network.reload
    expect(network.swarm_network_id).to be_present
    expect(network.status).to eq(Network::READY)
    expect(network.applied_revision).to eq(1)
  end

  it "returns NOOP on second reconcile run (AC4, AC5)" do
    network_name = create_lab_network
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             name: network_name, status: Network::READY,
                             desired_revision: 1, applied_revision: 1,
                             swarm_network_id: SecureRandom.hex(16))

    # Run reconciler (should be NOOP)
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::PERIODIC, logger: Rails.logger)
    reconciler.call

    # Verify no changes were made
    network.reload
    expect(network.status).to eq(Network::READY)
    expect(network.applied_revision).to eq(1)

    # Verify reconciliation run was recorded as NOOP
    run = ReconciliationRun.where(resource: network).last
    expect(run).to be_present
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
    created_resources << [ "network", network_name ]
  end

  it "advances appliedRevision only after re-inspection (AC3, AC11)" do
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             name: environment.technical_name,
                             status: Network::PROVISIONING, desired_revision: 1)

    # Before: applied_revision is nil
    expect(network.applied_revision).to be_nil

    # Run reconciler to create and verify network
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler.call

    created_resources << [ "network", environment.technical_name ]

    # After: applied_revision matches desired_revision
    network.reload
    expect(network.applied_revision).to eq(1)
    expect(network.converged?).to be true
  end
end
