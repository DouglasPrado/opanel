require "rails_helper"

# M01-18 AC6 — a version conflict on update results in CONFLICT, re-observation
# and a recomputed diff.
#
# Every update carries the `Version.Index` the caller observed when it computed
# its diff. If something moved in between, the Engine refuses the write instead
# of silently overwriting it — that is the compare-and-set the transport exists
# for, and it is the case a CLI cannot produce on demand.
#
# The race here is real: the runtime version is moved by a separate update, run
# against the daemon in the moment between this reconciler's inspection and its
# own write.
RSpec.describe "a version conflict on update, against a real Engine", :swarm, :integration, :service_lab do
  # Moves `Version.Index` behind the reconciler's back, the way another worker
  # or an operator with the CLI would.
  def move_the_runtime_version
    Opanel::Gates::SwarmLab.docker!("service", "update", "--detach",
      "--label-add", "moved.by=another-writer", service.technical_name)
  end

  it "answers CONFLICT, re-observes, recomputes the diff and converges (AC6)" do
    reconcile

    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    racing = LabRacingClient.new(before: "POST /services") { move_the_runtime_version }
    result = reconcile(executor: SwarmExecutor.new(client: racing))

    expect(racing.interfered).to be(true)
    expect(result).to be_success, -> { "the pass did not converge: #{result.code} #{result.message}" }
    expect(swarm_service.dig("Spec", "Mode", "Replicated", "Replicas")).to eq(2)
    expect(service.reload.applied_revision).to eq(service.desired_revision)
  end

  it "records the conflicting pass, and does not report it as success" do
    reconcile

    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    racing = LabRacingClient.new(before: "POST /services") { move_the_runtime_version }
    reconcile(executor: SwarmExecutor.new(client: racing))

    runs = ReconciliationRun.for_resource("Service", service.id).order(:id)
    conflicted = runs.find { |run| run.error_reason.to_s.match?(/revision moved/i) }
    expect(conflicted).to be_present
    expect(conflicted.result).to eq(ReconciliationRun::FAILED)
    expect(runs.last.result).to eq(ReconciliationRun::SUCCESS)
  end

  it "never overwrites what moved: the other writer's change survives" do
    reconcile

    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    racing = LabRacingClient.new(before: "POST /services") { move_the_runtime_version }
    reconcile(executor: SwarmExecutor.new(client: racing))

    # The label another writer added is still there, because the stale write was
    # refused rather than applied over it.
    expect(swarm_service.dig("Spec", "Labels", "moved.by")).to eq("another-writer")
  end

  it "leaves exactly one Service behind" do
    reconcile
    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    racing = LabRacingClient.new(before: "POST /services") { move_the_runtime_version }
    reconcile(executor: SwarmExecutor.new(client: racing))

    expect(swarm_services_named).to eq(1)
  end
end
