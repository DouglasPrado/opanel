require "rails_helper"

RSpec.describe "Network isolation between Environments", type: :integration, swarm: true do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }

  it "creates distinct networks for two environments (AC8)" do
    env1 = create(:environment, project: project, cluster: cluster, team: team,
                               name: "prod")
    env2 = create(:environment, project: project, cluster: cluster, team: team,
                               name: "staging")

    network1 = create(:network, environment: env1, cluster: cluster, team: team,
                               name: env1.technical_name,
                               status: Network::PROVISIONING, desired_revision: 1)
    network2 = create(:network, environment: env2, cluster: cluster, team: team,
                               name: env2.technical_name,
                               status: Network::PROVISIONING, desired_revision: 1)

    # Networks have different names
    expect(network1.technical_name).not_to eq(network2.technical_name)

    # Create both networks through reconciliation
    executor = SwarmExecutor.new
    reconciler1 = NetworkReconciler.new(environment: env1, executor: executor,
                                        trigger: ReconciliationRun::MANUAL, logger: Rails.logger)
    reconciler2 = NetworkReconciler.new(environment: env2, executor: executor,
                                        trigger: ReconciliationRun::MANUAL, logger: Rails.logger)

    reconciler1.call
    reconciler2.call

    # Verify both networks exist and have different Swarm IDs
    expect(lab_resource_exists?("network", network1.technical_name)).to be true
    expect(lab_resource_exists?("network", network2.technical_name)).to be true

    network1.reload
    network2.reload

    expect(network1.swarm_network_id).not_to eq(network2.swarm_network_id)
    created_resources << [ "network", network1.technical_name ]
    created_resources << [ "network", network2.technical_name ]
  end
end
