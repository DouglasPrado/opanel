require "rails_helper"

RSpec.describe "Unowned network BLOCKED scenario", type: :integration, swarm: true do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster, team: team) }

  it "BLOCKs when unowned network exists with same name (AC6)" do
    # Create an environment-specific network name
    network_name = lab_name("net")

    # Create a network in Swarm without platform labels (unowned)
    unowned_net = create_lab_network(name: network_name)
    expect(lab_resource_exists?("network", unowned_net)).to be true

    # Create desired network record pointing to the unowned network
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             name: network_name, status: Network::PROVISIONING, desired_revision: 1)

    # Run reconciler - it should detect the unowned network and BLOCK
    executor = SwarmExecutor.new
    reconciler = NetworkReconciler.new(environment: environment, executor: executor,
                                       trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler.call

    # Verify the reconciliation run was recorded as BLOCKED
    network.reload
    run = ReconciliationRun.where(resource: network).last
    expect(run).to be_present
    expect(run.result).to eq(ReconciliationRun::BLOCKED)
    expect(run.error_reason).to be_present
  end
end
