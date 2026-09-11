require "rails_helper"

RSpec.describe ReconciliationRun, type: :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster, team: team) }
  let(:network) { create(:network, environment: environment, cluster: cluster, team: team) }

  it "persists a reconciliation run" do
    run = ReconciliationRun.create!(
      resource: network,
      team_id: team.id,
      trigger: ReconciliationRun::PERIODIC,
      diff_class: ReconciliationRun::NOOP,
      actions_applied: [],
      result: ReconciliationRun::SUCCESS,
      observed_at: Time.current
    )

    expect(run.persisted?).to be true
    expect(run.resource).to eq(network)
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
  end

  it "enforces error_reason required when result is not SUCCESS" do
    # Create a record and then try to update with invalid data
    run = ReconciliationRun.create!(
      resource: network,
      team_id: team.id,
      trigger: ReconciliationRun::PERIODIC,
      diff_class: ReconciliationRun::NOOP,
      actions_applied: [],
      result: ReconciliationRun::SUCCESS,
      observed_at: Time.current
    )

    # Now update to BLOCKED without error_reason (should be invalid)
    run.result = ReconciliationRun::BLOCKED
    run.error_reason = nil

    expect(run.valid?).to be false
    expect(run.errors[:error_reason]).to be_present
  end

  it "allows multiple runs for the same resource" do
    run1 = create_reconciliation_run(network, ReconciliationRun::NOOP)
    run2 = create_reconciliation_run(network, ReconciliationRun::CREATE)

    expect(ReconciliationRun.for_resource("Network", network.id).count).to eq(2)
  end

  private

  def create_reconciliation_run(resource, diff_class)
    ReconciliationRun.create!(
      resource: resource,
      team_id: team.id,
      trigger: ReconciliationRun::PERIODIC,
      diff_class: diff_class,
      actions_applied: [],
      result: ReconciliationRun::SUCCESS,
      observed_at: Time.current
    )
  end
end
