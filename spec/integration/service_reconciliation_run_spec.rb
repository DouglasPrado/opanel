require "rails_helper"

# M01-18 AC13 — every execution persists a ReconciliationRun with its diff, its
# actions and its result.
#
# The run is what makes a reconcile answerable without reproducing it: it says
# what the reconciler saw, what it decided, what it did and how it ended. A run
# that is not SUCCESS carries the reason, and PostgreSQL enforces that rather
# than trusting the writer.
RSpec.describe "Service ReconciliationRun", type: :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) do
    create(:service, environment: environment, team: team, replicas: 2, status: Service::PROVISIONING,
      image_ref: "docker.io/busybox:latest", image_digest: "sha256:#{'a' * 64}")
  end
  let!(:network) do
    create(:network, environment: environment, team: team, cluster: environment.cluster,
      swarm_network_id: "abc123", status: Network::READY)
  end

  def converging_script
    observed = service_observation(service)
    { "inspect_service" => [ not_found, applied(observed) ], "create_service" => applied(observed),
      "list_tasks" => tasks }
  end

  def reconcile(script, trigger: ReconciliationRun::PERIODIC)
    ServiceReconciler.call(service: service, trigger: trigger, executor: FakeSwarmExecutor.new(script))
  end

  def runs = ReconciliationRun.for_resource("Service", service.id).order(:created_at)

  it "persists exactly one run per execution" do
    reconcile(converging_script)
    reconcile({ "inspect_service" => applied(service_observation(service)), "list_tasks" => tasks })

    expect(runs.count).to eq(2)
  end

  it "records the trigger that caused it" do
    reconcile(converging_script, trigger: ReconciliationRun::OPERATION)

    expect(runs.last.trigger).to eq(ReconciliationRun::OPERATION)
  end

  it "records the diff class and the actions applied" do
    reconcile(converging_script)

    expect(runs.last.diff_class).to eq(ReconciliationRun::CREATE)
    expect(runs.last.actions_applied).to eq([ { "action" => "create", "name" => service.technical_name } ])
  end

  it "records an empty action list for a pass that changed nothing" do
    reconcile({ "inspect_service" => applied(service_observation(service)), "list_tasks" => tasks })

    expect(runs.last.diff_class).to eq(ReconciliationRun::NOOP)
    expect(runs.last.actions_applied).to eq([])
  end

  it "carries the reason when the result is BLOCKED" do
    service.update_columns(image_digest: nil)
    reconcile({ "inspect_service" => not_found })

    expect(runs.last.result).to eq(ReconciliationRun::BLOCKED)
    expect(runs.last.error_reason).to be_present
  end

  it "is scoped to the Service's own Team" do
    reconcile(converging_script)

    expect(runs.last.team_id).to eq(team.id)
    expect(runs.last.resource).to eq(service)
  end

  it "cannot be stored without a reason when it did not succeed" do
    run = ReconciliationRun.create!(resource: service, team_id: team.id,
      trigger: ReconciliationRun::PERIODIC, diff_class: ReconciliationRun::CREATE,
      result: ReconciliationRun::SUCCESS, observed_at: Time.current)

    expect { run.update!(result: ReconciliationRun::FAILED) }
      .to raise_error(ActiveRecord::RecordInvalid, /required when result is not SUCCESS/)
  end

  it "keeps one Team's runs out of another's" do
    other = create(:team)
    reconcile(converging_script)

    expect(ReconciliationRun.where(team_id: other.id)).to be_empty
  end
end
