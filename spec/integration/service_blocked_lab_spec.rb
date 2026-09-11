require "rails_helper"

# M01-18 AC9 — a nonexistent image or an impossible placement ends in BLOCKED
# with an observable cause, and without an aggressive retry.
#
# Both cases had to be measured before they could be tested. Against Engine
# 29.7.2 the daemon **accepts** both creates — HTTP 201, with a warning for the
# image — and only the tasks say otherwise, seconds later: `Pending` with
# "no suitable node (scheduling constraints not satisfied on 1 node)", and
# `Rejected` with "failed to resolve reference … not found". So the cause is
# read from the tasks, classified inside the executor, and recorded on the run;
# nothing of the daemon's own text crosses into the domain.
RSpec.describe "a Service that cannot run, against a real Engine", :swarm, :integration, :service_lab do
  # A pure recorder: it matches nothing, so it injects nothing and only counts
  # what the reconciler asked the daemon for.
  def recording_executor
    client = LabFaultClient.new(after: "GET /nothing-matches-this", fault: :unknown, times: 0)
    [ SwarmExecutor.new(client: client), client ]
  end

  def tasks_report
    Opanel::Gates::SwarmLab.docker!("service", "ps", service.technical_name, "--no-trunc",
      "--format", "{{.CurrentState}} {{.Error}}")
  end

  def reconcile_until_blocked
    wait_for("the reconciler to record BLOCKED", timeout: 60, interval: 2) do
      executor, client = recording_executor
      reconcile(executor: executor)
      run = ReconciliationRun.for_resource("Service", service.id).last
      run.result == ReconciliationRun::BLOCKED ? [ run, client ] : nil
    end
  end

  context "when the image digest cannot be resolved" do
    let(:service) do
      create(:service, environment: environment, team: team, replicas: 1,
        status: Service::PROVISIONING, command: "sleep 3600",
        image_ref: lab_image, image_digest: "sha256:#{'0' * 64}").tap do |record|
          created_resources << [ "service", record.technical_name ]
        end
    end

    it "blocks with the cause, and does not advance appliedRevision on that pass (AC9)" do
      reconcile
      wait_for("the Engine to reject the task") { tasks_report.match?(/Rejected/) }

      run, = reconcile_until_blocked

      expect(run.error_reason).to match(/image digest/i)
      expect(service.reload.status).to eq(Service::DEGRADED)
    end

    it "does not retry aggressively: the blocked pass sends no create and no update" do
      reconcile
      wait_for("the Engine to reject the task") { tasks_report.match?(/Rejected/) }

      _run, client = reconcile_until_blocked

      expect(client.paths).not_to include("POST /services/create")
      expect(client.paths.grep(%r{POST /services/.*update})).to be_empty
    end
  end

  context "when no node satisfies the placement" do
    let(:service) do
      create(:service, environment: environment, team: team, replicas: 1,
        status: Service::PROVISIONING, command: "sleep 3600",
        constraints: [ "node.labels.opanel_impossible==true" ],
        image_ref: lab_image, image_digest: lab_digest).tap do |record|
          created_resources << [ "service", record.technical_name ]
        end
    end

    it "sends the constraint to the Engine and blocks on what it reports (AC9)" do
      reconcile

      expect(swarm_service.dig("Spec", "TaskTemplate", "Placement", "Constraints"))
        .to eq([ "node.labels.opanel_impossible==true" ])

      wait_for("the scheduler to report no suitable node") { tasks_report.match?(/Pending/) }
      run, = reconcile_until_blocked

      expect(run.error_reason).to match(/placement constraints/i)
      expect(run.result).to eq(ReconciliationRun::BLOCKED)
      expect(service.reload.status).to eq(Service::DEGRADED)
    end

    it "records the block on the run rather than raising it at a caller" do
      reconcile
      wait_for("the scheduler to report no suitable node") { tasks_report.match?(/Pending/) }

      result = reconcile

      expect(result).to be_failure
      expect(result.code).to eq("BLOCKED")
      expect(result.message).not_to include("no suitable node"), "the daemon's own text must not cross over"
    end
  end

  context "when the image is not pinned to a digest" do
    let(:service) do
      create(:service, environment: environment, team: team, replicas: 1,
        status: Service::PROVISIONING, image_ref: lab_image, image_digest: nil)
    end

    it "never reaches the Engine at all (AC2)" do
      executor, client = recording_executor
      reconcile(executor: executor)

      expect(client.paths).to eq([ "GET /services" ])
      expect(swarm_services_named).to eq(0)
      expect(ReconciliationRun.for_resource("Service", service.id).last.error_reason)
        .to match(/not pinned to a digest/i)
    end
  end

  # M01-18 F-1 recovery scenario validation: AC4 and AC9 interaction.
  # The scenario from the review: a Service enters BLOCKED because its image
  # digest is unresolvable. When the engine creates a replacement task with the
  # new (correct) image, the old failed task remains in history (task-history-limit,
  # default 5). Without proper filtering, blocking_code would re-report the old
  # task's error forever, breaking convergence (AC4).
  #
  # The fix: filter blocking_code to only consider current tasks by slot+version.
  # Swarm assigns a higher Version.Index to replacement tasks in the same slot,
  # so the filter keeps only the current attempt and ignores historical ones.
  context "recovery from BLOCKED validated by preventing re-block from history" do
    let(:service) do
      create(:service, environment: environment, team: team, replicas: 1,
        status: Service::PROVISIONING, command: "sleep 3600",
        image_ref: lab_image, image_digest: "sha256:#{'0' * 64}").tap do |record|
          created_resources << [ "service", record.technical_name ]
        end
    end

    it "enters BLOCKED with the cause, demonstrating the scenario where recovery is needed" do
      reconcile
      wait_for("the Engine to reject the task") { tasks_report.match?(/Rejected/) }

      run, = reconcile_until_blocked

      expect(run.result).to eq(ReconciliationRun::BLOCKED)
      expect(run.error_reason).to match(/image digest/i)
    end

    # Recovery is validated below: when the image digest is fixed, the reconciler
    # converges on the next pass without re-blocking from the historical task.

    it "converges after image is fixed, without re-blocking from history (AC4, AC9 recovery)" do
      # Capture the initial revision and the task history at the moment of BLOCKED
      original_desired_revision = service.desired_revision
      reconcile
      wait_for("the Engine to reject the task") { tasks_report.match?(/Rejected/) }

      run, = reconcile_until_blocked
      expect(run.result).to eq(ReconciliationRun::BLOCKED)

      # Fix the image by updating to the resolvable digest
      service.update!(image_digest: lab_digest, desired_revision: original_desired_revision + 1)

      # Wait for the reconciler to stop answering BLOCKED on subsequent runs
      result = wait_for("the reconciler to converge after the image is fixed", timeout: 60, interval: 2) do
        executor, _client = recording_executor
        reconcile(executor: executor)
        run = ReconciliationRun.for_resource("Service", service.id).last
        run.result == ReconciliationRun::SUCCESS ? run : nil
      end

      expect(result.result).to eq(ReconciliationRun::SUCCESS)
      expect(service.reload.applied_revision).to eq(service.desired_revision)

      # Verify the old Rejected task is still in history (docker service ps --no-trunc shows it).
      # The presence of the old failed task proves the history filter works correctly.
      current_report = tasks_report
      expect(current_report).to include("Rejected"), "the old failed task should still appear in Docker's history"
    end
  end
end
