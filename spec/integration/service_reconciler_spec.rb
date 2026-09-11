require "rails_helper"

# M01-18 — the reconciler's sequence and what it is allowed to write.
#
# The real Engine proves the outcome (`service_*_lab_spec.rb`); this file proves
# the algorithm around it: inspect before deciding, observe before repeating,
# release the lease under the identity that took it, and never touch the
# operator's intent.
RSpec.describe ServiceReconciler, type: :integration do
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

  def reconcile(script, **options)
    executor = FakeSwarmExecutor.new(script)
    result = described_class.call(service: service, executor: executor, **options)
    [ result, executor ]
  end

  def create_script(observation: nil, tasks_result: nil)
    observed = observation || service_observation(service)
    {
      "inspect_service" => [ not_found, applied(observed) ],
      "create_service" => applied(observed),
      "list_tasks" => tasks_result || tasks
    }
  end

  describe "the first convergence (AC1, AC10)" do
    it "inspects before it decides, creates, re-inspects, and only then advances appliedRevision" do
      _result, executor = reconcile(create_script)

      expect(executor.types).to eq(%w[inspect_service create_service inspect_service list_tasks])
      expect(service.reload.applied_revision).to eq(service.desired_revision)
      expect(service.swarm_service_id).to eq("runtime1")
    end

    it "records the run with its diff class, its actions and its result (AC13)" do
      reconcile(create_script)

      run = ReconciliationRun.for_resource("Service", service.id).last
      expect(run.diff_class).to eq(ReconciliationRun::CREATE)
      expect(run.result).to eq(ReconciliationRun::SUCCESS)
      expect(run.actions_applied.first["action"]).to eq("create")
      expect(run.team_id).to eq(team.id)
      expect(run.observed_at).to be_present
    end

    it "audits the deploy as a privileged action with no human actor" do
      reconcile(create_script)

      entry = AuditLog.for_resource("Service", service.id).first
      expect(entry.action).to eq("service.deployed")
      expect(entry.actor_type).to eq("SYSTEM")
      expect(entry.team_id).to eq(team.id)
    end
  end

  describe "idempotence (AC4)" do
    it "answers NOOP on the second pass and sends no mutation" do
      reconcile(create_script)
      _result, executor = reconcile({ "inspect_service" => applied(service_observation(service)),
        "list_tasks" => tasks })

      # An inspection and a task read: both are reads. Nothing is mutated.
      expect(executor.types).to eq(%w[inspect_service list_tasks])
      expect(ReconciliationRun.for_resource("Service", service.id).last.diff_class)
        .to eq(ReconciliationRun::NOOP)
    end
  end

  describe "a lost Docker response (AC5)" do
    it "observes the runtime before repeating a create, and never sends a second blind one" do
      observed = service_observation(service)
      _result, executor = reconcile({
        "inspect_service" => [ not_found, applied(observed), applied(observed) ],
        "create_service" => unknown_outcome,
        "list_tasks" => tasks
      })

      # inspect → create (answer lost) → inspect → (already there: no second create) → inspect → tasks
      expect(executor.types.count("create_service")).to eq(1)
      expect(executor.types[1]).to eq("create_service")
      expect(executor.types[2]).to eq("inspect_service")
      expect(service.reload.applied_revision).to eq(service.desired_revision)
    end
  end

  describe "appliedRevision as a claim about the runtime (AC10)" do
    it "does not advance when the re-inspection finds nothing" do
      reconcile({ "inspect_service" => [ not_found, not_found ], "create_service" => applied(nil) })

      expect(service.reload.applied_revision).to be_nil
      expect(ReconciliationRun.for_resource("Service", service.id).last.result)
        .to eq(ReconciliationRun::FAILED)
    end

    it "does not advance when the re-inspection shows a different revision of the spec" do
      stale = service_observation(service, replicas: 99)
      reconcile({ "inspect_service" => [ not_found, applied(stale) ], "create_service" => applied(stale) })

      expect(service.reload.applied_revision).to be_nil
    end

    it "does not advance when the tasks cannot be scheduled (AC9)" do
      reconcile(create_script(tasks_result: tasks(blocking_code: "PLACEMENT_IMPOSSIBLE")))

      expect(service.reload.applied_revision).to be_nil
      expect(service.status).to eq(Service::DEGRADED)

      run = ReconciliationRun.for_resource("Service", service.id).last
      expect(run.result).to eq(ReconciliationRun::BLOCKED)
      expect(run.error_reason).to match(/placement constraints/i)
    end
  end

  describe "BLOCKED without an Engine call (AC2, AC9)" do
    it "refuses to deploy an image that is not pinned to a digest, and asks the daemon for nothing" do
      service.update_columns(image_digest: nil)
      _result, executor = reconcile({ "inspect_service" => not_found })

      expect(executor.types).to eq(%w[inspect_service])
      run = ReconciliationRun.for_resource("Service", service.id).last
      expect(run.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(run.error_reason).to match(/digest/i)
      expect(service.reload.status).to eq(Service::DEGRADED)
    end

    it "does not retry aggressively: a blocked pass sends one inspect and stops" do
      service.update_columns(image_digest: nil)
      _result, executor = reconcile({ "inspect_service" => not_found })

      expect(executor.calls.length).to eq(1)
    end
  end

  describe "the lease (doc 07 §14)" do
    it "acquires on the Service's own scope and releases under the identity that took it" do
      expect(ReleaseResourceLock).to receive(:call)
        .with(hash_including(worker_identity: Opanel::WorkerIdentity.current))
        .and_call_original

      reconcile(create_script)

      expect(ResourceLock.find_by(scope_key: "service:#{service.id}")).to be_present
    end

    it "releases the lease even when the pass raises" do
      expect { reconcile({ "inspect_service" => ->(_c) { raise "engine exploded" } }) }
        .to raise_error("engine exploded")

      lock = ResourceLock.find_by(scope_key: "service:#{service.id}")
      expect(lock.lease_until).to be <= Time.current
    end

    it "does nothing at all when the lease is held by somebody else" do
      AcquireResourceLock.call(team: team, scope_key: "service:#{service.id}", ttl_seconds: 60)
      allow(Opanel::WorkerIdentity).to receive(:current).and_return("another-worker")

      result, executor = reconcile({ "inspect_service" => not_found })

      expect(result).to be_failure
      expect(executor.calls).to be_empty
    end
  end

  describe "user intent (AF-03)" do
    it "changes no column the operator owns" do
      intent = service.attributes.slice("name", "slug", "image_ref", "replicas", "ports",
        "health_check", "cpu_limit", "cpu_reservation", "memory_limit", "memory_reservation",
        "constraints", "desired_revision")

      reconcile(create_script)

      expect(service.reload.attributes.slice(*intent.keys)).to eq(intent)
    end

    it "never declares the Service RUNNING: derived status is observed, not stored (M01-19)" do
      reconcile(create_script)

      expect(service.reload.status).to eq(Service::PROVISIONING)
    end
  end

  # doc 07 §11.2: Operations accelerate, the sweep guarantees. A Service left
  # unconverged by a worker that died, or by an Operation nobody consumed, is
  # found by looking again — which is the only reason the platform converges at
  # all after a Control Plane restart.
  describe "the cadence (ReconcileServicesJob)" do
    it "reconciles a Service whose applied revision is behind its desired one" do
      service.update!(applied_revision: nil)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform

      expect(ServiceReconciler).to have_received(:call)
        .with(hash_including(service: service, trigger: ReconciliationRun::PERIODIC))
    end

    it "leaves a converged Service alone" do
      service.update!(applied_revision: service.desired_revision)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform

      expect(ServiceReconciler).not_to have_received(:call)
    end

    it "never reconciles a DRAFT Service: nobody has asked for it yet" do
      service.update!(status: Service::DRAFT, applied_revision: nil)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform

      expect(ServiceReconciler).not_to have_received(:call)
    end

    it "consumes an open Operation with the OPERATION trigger, and claims it" do
      operation = create(:operation, team: team, resource_type: "Service", resource_id: service.id,
        type: "UPDATE_SERVICE", desired_revision: service.desired_revision, status: Operation::PENDING)
      allow(ServiceReconciler).to receive(:call)

      ReconcileServicesJob.new.perform(operation.id)

      expect(ServiceReconciler).to have_received(:call)
        .with(hash_including(trigger: ReconciliationRun::OPERATION, operation: operation))
      expect(operation.reload.status).to eq(Operation::QUEUED)
    end

    it "drives the Operation to SUCCEEDED when the pass converges" do
      operation = create(:operation, team: team, resource_type: "Service", resource_id: service.id,
        type: "UPDATE_SERVICE", desired_revision: service.desired_revision, status: Operation::PENDING)
      observed = service_observation(service)
      allow(SwarmExecutor).to receive(:new).and_return(FakeSwarmExecutor.new(
        "inspect_service" => [ not_found, applied(observed) ],
        "create_service" => applied(observed),
        "list_tasks" => tasks
      ))

      ReconcileServicesJob.new.perform(operation.id)

      expect(operation.reload.status).to eq(Operation::SUCCEEDED)
      expect(operation.finished_at).to be_present
    end

    it "does not stop the batch when one Service fails" do
      service.update!(applied_revision: nil)
      other = create(:service, environment: environment, team: team, status: Service::PROVISIONING)
      allow(ServiceReconciler).to receive(:call).and_raise("the Engine exploded")

      expect { ReconcileServicesJob.new.perform }.not_to raise_error
      expect(ServiceReconciler).to have_received(:call).with(hash_including(service: other))
    end
  end

  describe "tenancy" do
    it "writes nothing that reaches another Team" do
      other_team = create(:team)
      reconcile(create_script)

      expect(ReconciliationRun.where(team_id: other_team.id)).to be_empty
      expect(AuditLog.where(team_id: other_team.id)).to be_empty
      expect(ResourceLock.where(scope_key: "service:#{service.id}").pluck(:team_id)).to eq([ team.id ])
    end
  end
end
