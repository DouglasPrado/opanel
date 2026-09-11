require "rails_helper"

# M01-18 AC7 — restarting the reconciler in the middle of an operation does not
# duplicate the resource, proved against a real Swarm.
#
# The worker dies at the worst possible moment: the Engine has created the
# Service and the process disappears before anything was written down. The next
# run inherits a database that knows nothing and a daemon that already did the
# work. It must adopt, not create — `create_service` looks for the ownership
# label first (doc 07 §6.2), which is what makes the recovery idempotent instead
# of destructive.
RSpec.describe "a reconciler restarted mid-operation, against a real Engine", :swarm, :integration,
  :service_lab do
  def crash_after_create
    dying = SwarmExecutor.new(client: LabFaultClient.new(after: "POST /services/create", fault: :crash))

    expect { reconcile(executor: dying) }.to raise_error(LabFaultClient::WorkerDied)
  end

  it "creates no second Service when the worker dies and another takes over (AC7)" do
    crash_after_create
    expect(swarm_services_named).to eq(1)

    reconcile

    expect(swarm_services_named).to eq(1)
  end

  it "leaves the database knowing nothing, and the next pass adopts what is there" do
    crash_after_create

    expect(service.reload.swarm_service_id).to be_nil
    expect(service.applied_revision).to be_nil

    reconcile

    expect(service.reload.swarm_service_id).to eq(swarm_service["ID"])
    expect(service.applied_revision).to eq(service.desired_revision)
  end

  it "takes the lease again with a higher fencing token" do
    crash_after_create
    first_token = ResourceLock.find_by(scope_key: "service:#{service.id}").fencing_token

    reconcile

    expect(ResourceLock.find_by(scope_key: "service:#{service.id}").fencing_token).to be > first_token
  end

  it "observes before it acts: the successor inspects before any create" do
    crash_after_create
    observed = LabFaultClient.new(after: "GET /nothing-matches-this", fault: :unknown, times: 0)

    reconcile(executor: SwarmExecutor.new(client: observed))

    expect(observed.paths.first).to eq("GET /services")
    expect(observed.paths).not_to include("POST /services/create")
  end

  it "records the adoption rather than a second creation" do
    crash_after_create

    reconcile

    run = ReconciliationRun.for_resource("Service", service.id).last
    expect(run.result).to eq(ReconciliationRun::SUCCESS)
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
  end
end
