require "rails_helper"

RSpec.describe "Environment network operation", type: :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:actor) { create(:user) }

  before do
    create(:team_member, user: actor, team: team, role: "DEVELOPER", status: "ACTIVE")
  end

  it "creates Network and Operation in one transaction when Environment is created" do
    result = CreateEnvironment.call(actor: actor, project: project, cluster: cluster, name: "Test")

    expect(result.success?).to be true
    env = result.value[:environment]
    expect(env.network).to be_present
    expect(env.network.status).to eq(Network::PROVISIONING)
  end

  it "creates Operation with CREATE_NETWORK type" do
    result = CreateEnvironment.call(actor: actor, project: project, cluster: cluster, name: "Test2")
    env = result.value[:environment]

    operations = Operation.where(resource_type: "Network", resource_id: env.network.id, type: "CREATE_NETWORK")
    expect(operations).to be_present
  end

  it "creates OutboxEvent for the operation" do
    result = CreateEnvironment.call(actor: actor, project: project, cluster: cluster, name: "Test3")
    env = result.value[:environment]

    events = OutboxEvent.where(aggregate_type: "Network", aggregate_id: env.network.id)
    expect(events).to be_present
  end
end
