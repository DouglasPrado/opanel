require "rails_helper"

# M01-18 AC5 — a lost Docker response leads to re-observation, never to a blind
# repeat. Proved by fault injection against the real Engine.
#
# The fault is the one that matters: the create **reaches the daemon and
# succeeds**, and the answer is lost on the way back. A caller that retries
# blindly here creates a second Service, or fails on a name conflict and reports
# a failure for a deploy that actually happened. doc 07 §5.3 is explicit —
# *"nunca repetir cegamente: observar actual state primeiro"*.
RSpec.describe "a lost Docker response, against a real Engine", :swarm, :integration, :service_lab do
  let(:fault_client) { LabFaultClient.new(after: "POST /services/create", fault: :unknown) }
  let(:executor) { SwarmExecutor.new(client: fault_client) }

  it "observes the runtime before repeating, and leaves exactly one Service (AC5)" do
    reconcile(executor: executor)

    expect(swarm_services_named).to eq(1)
  end

  it "puts an inspection between the lost answer and any repeat" do
    reconcile(executor: executor)

    creates = fault_client.paths.each_index.select { |i| fault_client.paths[i] == "POST /services/create" }
    expect(creates.length).to eq(1), "the create was repeated blindly after an unknown outcome"

    after_the_create = fault_client.paths[(creates.first + 1)..]
    expect(after_the_create.first).to eq("GET /services")
  end

  it "converges: the Service the daemon kept is the one the database ends up describing" do
    reconcile(executor: executor)

    expect(service.reload.applied_revision).to eq(service.desired_revision)
    expect(service.swarm_service_id).to eq(swarm_service["ID"])
    expect(swarm_service.dig("Spec", "Labels", "com.opanel.service_id")).to eq(service.external_id)
  end

  it "does not report the deploy as failed: nothing is known to have failed" do
    reconcile(executor: executor)

    run = ReconciliationRun.for_resource("Service", service.id).last
    expect(run.result).to eq(ReconciliationRun::SUCCESS)
  end
end
