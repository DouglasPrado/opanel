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

  it "AC4: second reconcile run returns NOOP" do
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             status: Network::PROVISIONING, desired_revision: 1)

    # First run: create the network with platform labels
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler.call

    network.reload
    expect(network.status).to eq(Network::READY), "After first run, network should be READY"
    expect(network.applied_revision).to eq(1), "After first run, applied_revision should be 1"
    first_swarm_id = network.swarm_network_id
    expect(first_swarm_id).to be_present, "First run should set swarm_network_id"

    # Verify network exists in Swarm with correct name and labels
    expect(lab_resource_exists?("network", network.technical_name)).to be true
    created_resources << [ "network", network.technical_name ]

    first_run = ReconciliationRun.where(resource: network).order(:created_at).last
    expect(first_run.result).to eq(ReconciliationRun::SUCCESS)
    expect(first_run.diff_class).to eq(ReconciliationRun::CREATE)

    # Second run: should be NOOP
    executor2 = SwarmExecutor.new
    reconciler2 = NetworkReconciler.new(environment: environment, executor: executor2,
                                        trigger: ReconciliationRun::PERIODIC, logger: Rails.logger)
    reconciler2.call

    network.reload
    expect(network.status).to eq(Network::READY)
    expect(network.applied_revision).to eq(1)
    expect(network.swarm_network_id).to eq(first_swarm_id)

    run = ReconciliationRun.where(resource: network).order(:created_at).last
    expect(run).to be_present
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
  end

  it "AC5: network created with platform labels is recognised NOOP and not recreated" do
    # Create a network in Swarm with platform labels directly
    labels = Opanel::Ownership.labels_for(environment)
    technical_name = Opanel::Ownership.technical_name_for(environment)

    # Build docker label arguments from the labels hash
    label_args = labels.flat_map { |k, v| [ "--label", "#{k}=#{v}" ] }

    # Create network in Swarm with platform labels
    Opanel::Gates::SwarmLab.docker!(
      "network", "create", "--driver", "overlay",
      "--label", "#{lab_label}=true",
      *label_args,
      technical_name
    )
    created_resources << [ "network", technical_name ]

    # Create the desired network record
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             status: Network::PROVISIONING, desired_revision: 1)

    # Run reconciler - should recognize the existing network and be NOOP
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler.call

    network.reload
    expect(network.status).to eq(Network::READY)
    expect(network.applied_revision).to eq(1)
    expect(network.swarm_network_id).to be_present

    run = ReconciliationRun.where(resource: network).last
    expect(run).to be_present
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
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
