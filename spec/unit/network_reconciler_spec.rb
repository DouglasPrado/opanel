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
      executor_response = instance_double(ExecutionResult,
        outcome: ExecutionResult::NOOP,
        observed: nil
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
      executor_response = instance_double(ExecutionResult,
        outcome: ExecutionResult::NOOP,
        observed: nil
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

  describe "creation with ownership labels" do
    it "creates a network with project_id in labels and converges to READY" do
      network = create(:network, environment: environment, cluster: cluster, team: team,
                                status: Network::PROVISIONING, desired_revision: 1,
                                applied_revision: nil, swarm_network_id: nil)

      lock_double = instance_double(ResourceLock, fencing_token: "token_123")
      allow(AcquireResourceLock).to receive(:call).and_return(
        Opanel::Result.success(lock_double)
      )
      allow(ReleaseResourceLock).to receive(:call)

      # Create a verifying double that captures commands
      executor_double = double("executor")
      captured_commands = []

      # The reconciler will make two calls:
      # 1. inspect_network (returns nil, so network doesn't exist)
      # 2. create_network (returns APPLIED with the created network ID)
      # 3. inspect_network again to re-verify after creation

      allow(executor_double).to receive(:execute) do |command|
        captured_commands << command

        case command.type
        when "inspect_network"
          # First inspect returns nil (network doesn't exist)
          # Second inspect returns the created network with proper labels
          if captured_commands.length == 1
            # First inspect - network doesn't exist
            instance_double(ExecutionResult,
              outcome: ExecutionResult::NOOP,
              observed: nil
            )
          else
            # Re-inspection after create - return a properly labeled network observation
            observation = Opanel::RuntimeObservation.new(
              kind: "network",
              runtime_id: "nettest123abc",
              name: network.technical_name,
              labels: {
                "com.opanel.managed" => "true",
                "com.opanel.team_id" => team.external_id,
                "com.opanel.project_id" => project.external_id,
                "com.opanel.environment_id" => environment.external_id
              },
              version: nil,
              attributes: { "driver" => "overlay" }
            )
            instance_double(ExecutionResult,
              outcome: ExecutionResult::NOOP,
              observed: observation
            )
          end
        when "create_network"
          # Create returns APPLIED
          instance_double(ExecutionResult,
            outcome: ExecutionResult::APPLIED,
            runtime_resource_ids: [ "nettest123abc" ],
            observed: nil
          )
        end
      end

      NetworkReconciler.call(environment: environment, executor: executor_double, logger: Rails.logger)

      # Verify that the create command included the labels with project_id
      create_command = captured_commands.find { |cmd| cmd.type == "create_network" }
      expect(create_command).not_to be_nil,
"Expected a create_network command but got: #{captured_commands.map(&:type).inspect}"
      expect(create_command.payload).not_to be_nil, "Payload is nil for create_network command"
      # Note: ExecutorCommand stringifies all payload keys
      expect(create_command.payload["labels"]).to include("com.opanel.project_id")
      expect(create_command.payload["labels"]).to include("com.opanel.environment_id")
      expect(create_command.payload["labels"]).to include("com.opanel.team_id")

      # Verify network converged to READY
      network.reload
      expect(network.status).to eq(Network::READY)
      expect(network.applied_revision).to eq(network.desired_revision)
    end
  end
end
