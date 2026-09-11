require "rails_helper"

RSpec.describe "Network applied_revision tracking", type: :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster, team: team) }

  it "starts with applied_revision nil" do
    network = create(:network, environment: environment, cluster: cluster, team: team,
                             status: Network::PROVISIONING, desired_revision: 1, applied_revision: nil)
    expect(network.applied_revision).to be_nil
  end

  it "database enforces applied_revision <= desired_revision" do
    expect {
      Network.create!(environment: environment, cluster: cluster, team: team, name: "test",
                     driver: "overlay", status: Network::PROVISIONING,
                     desired_revision: 1, applied_revision: 2)
    }.to raise_error(ActiveRecord::CheckViolation)
  end

  it "persists applied_revision after reconciliation" do
    network = create(:network, environment: environment, cluster: cluster, team: team)
    network.update!(applied_revision: network.desired_revision, status: Network::READY)

    expect(network.reload.applied_revision).to eq(network.desired_revision)
    expect(network.converged?).to be true
  end
end
