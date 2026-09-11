require "rails_helper"

# M01-18 AC8 — a newer revision during execution marks the previous one
# SUPERSEDED and converges to the newest.
#
# Two places decide it, and both are here:
#
#   * `ReconcileServicesJob`, before any Engine call, when several Operations
#     are open for one Service — the doc 07 §6 rule that stale configuration is
#     never sent rather than sent and then corrected;
#   * `ServiceReconciler`, when the Desired State moves between the inspection
#     and the apply — the case the job cannot see because it had already chosen.
RSpec.describe "Service supersession", type: :unit do
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

  def operation_for(revision)
    create(:operation, team: team, resource_type: "Service", resource_id: service.id,
      type: "UPDATE_SERVICE", desired_revision: revision, status: Operation::PENDING)
  end

  describe "in the job, before anything is sent to the Engine" do
    it "supersedes the older Operation and reconciles the newest revision" do
      older = operation_for(1)
      newer = operation_for(2)
      service.update!(desired_revision: 2)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform(older.id)

      expect(older.reload.status).to eq(Operation::SUPERSEDED)
      expect(ServiceReconciler).not_to have_received(:call)
      expect(newer.reload.status).to eq(Operation::PENDING)
    end

    it "does not supersede the newest open Operation" do
      newest = operation_for(3)
      operation_for(1)
      service.update!(desired_revision: 3)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform(newest.id)

      expect(newest.reload.status).to eq(Operation::QUEUED)
      expect(ServiceReconciler).to have_received(:call)
    end
  end

  describe "in the reconciler, when the Desired State moves mid-pass" do
    it "marks the operation SUPERSEDED and converges to the newest revision" do
      operation = operation_for(1)
      operation.update!(status: Operation::QUEUED)
      target = service.desired_revision

      # The inspection answers "absent"; by the time the pass is ready to apply,
      # the operator has saved again.
      inspections = 0
      executor = FakeSwarmExecutor.new(
        "inspect_service" => lambda { |_command|
          inspections += 1
          if inspections == 1
            service.update!(desired_revision: target + 1, replicas: 7)
            not_found
          else
            applied(service_observation(service.reload))
          end
        },
        "create_service" => ->(_c) { applied(service_observation(service.reload)) },
        "list_tasks" => tasks
      )

      ServiceReconciler.call(service: service, operation: operation, executor: executor)

      expect(operation.reload.status).to eq(Operation::SUPERSEDED)
      expect(service.reload.applied_revision).to eq(target + 1)
    end

    it "never lands appliedRevision on the revision it abandoned" do
      target = service.desired_revision
      inspections = 0
      executor = FakeSwarmExecutor.new(
        "inspect_service" => lambda { |_command|
          inspections += 1
          service.update!(desired_revision: target + 1) if inspections == 1
          inspections == 1 ? not_found : applied(service_observation(service.reload))
        },
        "create_service" => ->(_c) { applied(service_observation(service.reload)) },
        "list_tasks" => tasks
      )

      ServiceReconciler.call(service: service, executor: executor)

      expect(service.reload.applied_revision).not_to eq(target)
      expect(service.applied_revision).to eq(target + 1)
    end

    it "records why the abandoned pass did not converge" do
      target = service.desired_revision
      inspections = 0
      executor = FakeSwarmExecutor.new(
        "inspect_service" => lambda { |_command|
          inspections += 1
          service.update!(desired_revision: target + 1) if inspections == 1
          inspections == 1 ? not_found : applied(service_observation(service.reload))
        },
        "create_service" => ->(_c) { applied(service_observation(service.reload)) },
        "list_tasks" => tasks
      )

      ServiceReconciler.call(service: service, executor: executor)

      superseded_run = ReconciliationRun.for_resource("Service", service.id).order(:created_at).first
      expect(superseded_run.error_reason).to match(/superseded by #{target + 1}/)
    end
  end
end
