require "rails_helper"

RSpec.describe NetworkReconciler, type: :unit do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) do
    create(:environment, project: project, cluster: cluster, team: team)
  end

  describe "lease management" do
    it "acquires and releases a resource lock with fencing token" do
      network = create(:network, environment: environment, cluster: cluster, team: team,
                                status: Network::READY, desired_revision: 1,
                                applied_revision: 1, swarm_network_id: SecureRandom.hex(16))

      lock_double = instance_double(ResourceLock, fencing_token: "token_123")
      expect(AcquireResourceLock).to receive(:call).and_return(
        Opanel::Result.success(lock_double)
      )
      expect(ReleaseResourceLock).to receive(:call).with(
        hash_including(lock: lock_double, worker_identity: anything)
      )

      executor_double = double("executor")
      executor_response = double(
        outcome: ExecutionResult::NOOP,
        safe_metadata: { network_data: nil }
      )
      allow(executor_double).to receive(:execute).and_return(executor_response)

      NetworkReconciler.call(environment: environment, executor: executor_double, logger: Rails.logger)
    end
  end

  describe "logging and observability" do
    it "logs reconciliation start and completion" do
      network = create(:network, environment: environment, cluster: cluster, team: team,
                                status: Network::READY, desired_revision: 1,
                                applied_revision: 1, swarm_network_id: SecureRandom.hex(16))

      lock_double = instance_double(ResourceLock, fencing_token: "token_123")
      allow(AcquireResourceLock).to receive(:call).and_return(
        Opanel::Result.success(lock_double)
      )
      allow(ReleaseResourceLock).to receive(:call)

      executor_double = double("executor")
      executor_response = double(
        outcome: ExecutionResult::NOOP,
        safe_metadata: { network_data: nil }
      )
      allow(executor_double).to receive(:execute).and_return(executor_response)

      logger_double = double("logger")
      allow(logger_double).to receive(:info)
      allow(logger_double).to receive(:warn)
      allow(logger_double).to receive(:error)

      NetworkReconciler.call(environment: environment, trigger: ReconciliationRun::PERIODIC,
                            executor: executor_double, logger: logger_double)

      expect(logger_double).to have_received(:info).at_least(:once)
    end
  end
end
