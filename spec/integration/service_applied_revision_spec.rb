require "rails_helper"

# M01-18 AC10 — `appliedRevision` advances only after a re-inspection confirms
# the state.
#
# The column is a claim about the runtime, so every example here asks what
# happens when the claim would be false: the daemon answered but the resource is
# not there, the resource is there but is not ours, the spec that came back is
# not the one that was asked for. In each case the revision stays where it was,
# and the database refuses to let it pass the desired one in any case.
RSpec.describe "Service appliedRevision", type: :integration do
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

  def reconcile(script) = ServiceReconciler.call(service: service, executor: FakeSwarmExecutor.new(script))

  it "advances when the re-inspection shows the revision that was asked for" do
    observed = service_observation(service)
    reconcile("inspect_service" => [ not_found, applied(observed) ],
      "create_service" => applied(observed), "list_tasks" => tasks)

    expect(service.reload.applied_revision).to eq(service.desired_revision)
  end

  it "does not advance when the re-inspection shows a resource that is not ours" do
    foreign = service_observation(service, labels: { "com.opanel.managed" => "true" })
    reconcile("inspect_service" => [ not_found, applied(foreign) ],
      "create_service" => applied(foreign), "list_tasks" => tasks)

    expect(service.reload.applied_revision).to be_nil
  end

  it "does not advance when the observed image is not the digest that was asked for" do
    other = service_observation(service, image: "docker.io/busybox@sha256:#{'b' * 64}")
    reconcile("inspect_service" => [ not_found, applied(other) ],
      "create_service" => applied(other), "list_tasks" => tasks)

    expect(service.reload.applied_revision).to be_nil
  end

  it "advances on a NOOP pass when a previous run converged but the column lagged" do
    service.update!(applied_revision: nil)
    reconcile("inspect_service" => applied(service_observation(service)), "list_tasks" => tasks)

    expect(service.reload.applied_revision).to eq(service.desired_revision)
  end

  it "catches up to the newest revision rather than incrementing one at a time" do
    service.update!(desired_revision: 5, applied_revision: 1)
    observed = service_observation(service)
    reconcile("inspect_service" => applied(observed), "list_tasks" => tasks)

    expect(service.reload.applied_revision).to eq(5)
  end

  it "is refused by PostgreSQL if it would ever pass the desired revision" do
    expect { service.update_columns(applied_revision: service.desired_revision + 1) }
      .to raise_error(ActiveRecord::StatementInvalid, /services_applied_revision_not_ahead/)
  end

  it "records the runtime id it converged to, and the database refuses a second claim on it" do
    observed = service_observation(service)
    reconcile("inspect_service" => [ not_found, applied(observed) ],
      "create_service" => applied(observed), "list_tasks" => tasks)

    other = create(:service, environment: environment, team: team)
    expect(service.reload.swarm_service_id).to eq("runtime1")
    expect { other.update_columns(swarm_service_id: "runtime1") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
