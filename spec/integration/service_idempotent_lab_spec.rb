require "rails_helper"

# M01-18 AC4 — running the reconciler twice is idempotent: the second pass is a
# NOOP.
#
# Idempotence here is not "the code checks a flag". The executor looks for a
# resource carrying this Service's ownership label before creating one (doc 07
# §6.2), so the second pass finds what the first one made and changes nothing.
# Against a real Engine, "changed nothing" is checkable: the Swarm Service keeps
# its runtime id and its `Version.Index` does not move.
RSpec.describe "Service reconciliation, twice, against a real Engine", :swarm, :integration, :service_lab do
  it "answers NOOP on the second pass and leaves the runtime untouched (AC4)" do
    reconcile
    first = swarm_service

    reconcile

    second = swarm_service
    expect(second["ID"]).to eq(first["ID"])
    expect(second.dig("Version", "Index")).to eq(first.dig("Version", "Index"))
    expect(swarm_services_named).to eq(1)
  end

  it "records the second pass as NOOP with no action applied (AC13)" do
    reconcile
    reconcile

    run = ReconciliationRun.for_resource("Service", service.id).last
    expect(run.diff_class).to eq(ReconciliationRun::NOOP)
    expect(run.actions_applied).to eq([])
    expect(run.result).to eq(ReconciliationRun::SUCCESS)
  end

  it "keeps appliedRevision where it was rather than advancing it again" do
    reconcile
    applied = service.reload.applied_revision

    reconcile

    expect(service.reload.applied_revision).to eq(applied)
  end

  it "adopts the resource it already owns instead of creating a second one" do
    reconcile

    # A third pass, after the row lost track of the runtime id: the label is
    # what identifies the resource, so the platform finds it again anyway.
    service.update_columns(swarm_service_id: nil)
    reconcile

    expect(swarm_services_named).to eq(1)
    expect(service.reload.swarm_service_id).to eq(swarm_service["ID"])
  end
end
