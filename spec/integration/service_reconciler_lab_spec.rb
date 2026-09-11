require "rails_helper"

# M01-18 AC1, AC2, AC3, AC10, AC13 — against a real Engine (Annex D §7).
#
# This is the Story's central claim: a row in PostgreSQL becomes a Docker Swarm
# Service, identified by digest, attached to its Environment's overlay, carrying
# the labels that make it reconcilable — and the database only says so after the
# reconciler looked again and saw it.
RSpec.describe "the Service reconciler, against a real Engine", :swarm, :integration, :service_lab do
  it "creates a real Swarm Service carrying the ownership labels (AC1)" do
    reconcile

    expect(swarm_service_exists?).to be(true)
    labels = swarm_service.dig("Spec", "Labels")
    expect(labels["com.opanel.managed"]).to eq("true")
    expect(labels["com.opanel.service_id"]).to eq(service.external_id)
    expect(labels["com.opanel.environment_id"]).to eq(environment.external_id)
    expect(labels["com.opanel.team_id"]).to eq(team.external_id)
    expect(labels["com.opanel.desired_revision"]).to eq(service.desired_revision.to_s)
  end

  it "references the image by digest, not by tag (AC2)" do
    reconcile

    image = swarm_service.dig("Spec", "TaskTemplate", "ContainerSpec", "Image")
    expect(image).to include("@#{lab_digest}")
    expect(image).not_to eq(lab_image)
  end

  it "attaches the Environment's overlay and publishes no port (AC3)" do
    reconcile

    targets = Array(swarm_service.dig("Spec", "TaskTemplate", "Networks")).map { |n| n["Target"] }
    expect(targets).to eq([ lab_network_id ])
    expect(swarm_service["Spec"]["EndpointSpec"].to_h["Ports"].to_a).to be_empty
    expect(swarm_service["Endpoint"].to_h["Ports"].to_a).to be_empty
  end

  it "advances appliedRevision and records the runtime id only after re-inspection (AC10)" do
    reconcile

    expect(service.reload.applied_revision).to eq(service.desired_revision)
    expect(service.swarm_service_id).to eq(swarm_service["ID"])
  end

  it "persists the run with its diff, its actions and its result (AC13)" do
    reconcile(trigger: ReconciliationRun::OPERATION)

    run = ReconciliationRun.for_resource("Service", service.id).last
    expect(run.diff_class).to eq(ReconciliationRun::CREATE)
    expect(run.result).to eq(ReconciliationRun::SUCCESS)
    expect(run.trigger).to eq(ReconciliationRun::OPERATION)
    expect(run.actions_applied.first["action"]).to eq("create")
  end

  it "scales by applying the desired revision, without replacing the Service (AC8 path UPDATE_SAFE)" do
    reconcile
    runtime_id = swarm_service["ID"]

    service.update!(replicas: 2, desired_revision: service.desired_revision + 1)
    result = reconcile

    expect(result).to be_success, -> { "the scaling pass did not run: #{result.code} #{result.message}" }
    expect(ReconciliationRun.for_resource("Service", service.id).last.error_reason).to be_nil
    expect(swarm_service.dig("Spec", "Mode", "Replicated", "Replicas")).to eq(2)
    expect(swarm_service["ID"]).to eq(runtime_id)
    expect(service.reload.applied_revision).to eq(service.desired_revision)
    expect(ReconciliationRun.for_resource("Service", service.id).last.diff_class)
      .to eq(ReconciliationRun::UPDATE_SAFE)
  end

  it "rolls the tasks out when the spec changes in a way the observation cannot see" do
    reconcile

    service.update!(command: "sleep 7200", desired_revision: service.desired_revision + 1)
    reconcile

    expect(swarm_service.dig("Spec", "TaskTemplate", "ContainerSpec", "Command")).to eq(%w[sleep 7200])
    expect(ReconciliationRun.for_resource("Service", service.id).last.diff_class)
      .to eq(ReconciliationRun::ROLLOUT)
    expect(service.reload.applied_revision).to eq(service.desired_revision)
  end
end
