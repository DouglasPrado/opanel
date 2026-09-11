require "rails_helper"

# The two internal contracts of doc 07 §20, transcribed rather than read back
# from the code — a spec that iterates the constant it checks proves the constant
# equals itself. Renaming a field is a contract change and has to cost an edit
# here as well.
RSpec.describe "the executor contracts (doc 07 §20)", type: :contract do
  describe "Command (§20.1)" do
    COMMAND_FIELDS = %i[id type cluster_id resource_type resource_id desired_revision
      requested_by correlation_id idempotency_key payload].freeze

    it "carries exactly the fields §20.1 names" do
      expect(ExecutorCommand.members).to eq(COMMAND_FIELDS)
    end

    it "freezes its payload, so an operation cannot mutate what it was asked" do
      command = ExecutorCommand.new(id: "c", type: "inspect_service", cluster_id: "cl",
        resource_type: "Service", resource_id: "svc", payload: { image: "x" })

      expect(command.payload).to be_frozen
      expect(command.payload).to eq("image" => "x")
    end
  end

  describe "ExecutionResult (§20.2)" do
    RESULT_FIELDS = %i[command_id outcome observed_runtime_version runtime_resource_ids
      safe_metadata error_code observe_before_retry observed].freeze

    it "carries the fields §20.2 names, plus the one flag §5.3 requires, plus ADR-0009 observation" do
      expect(ExecutionResult.members).to eq(RESULT_FIELDS)
    end

    # The enum is the approved one. A sixth value would be a contract change.
    it "admits exactly the five outcomes of §20.2" do
      expect(ExecutionResult::OUTCOMES).to eq(%w[APPLIED NOOP CONFLICT RETRYABLE FAILED])
    end

    it "refuses an outcome outside the enum" do
      expect { ExecutionResult.new(command_id: "c", outcome: "UNKNOWN") }
        .to raise_error(ArgumentError, /unknown outcome/)
    end

    # doc 07 §5.3's sixth *situation* is not a sixth outcome: it is RETRYABLE with
    # the flag that says "observe before you do". It is never FAILED, because
    # nothing is known to have failed.
    it "represents an unknown outcome as RETRYABLE with observe_before_retry, never as FAILED" do
      command = ExecutorCommand.new(id: "c", type: "create_service", cluster_id: "cl",
        resource_type: "Service", resource_id: "svc")
      result = ExecutionResult.unknown(command)

      expect(result).to be_retryable
      expect(result).not_to be_failed
      expect(result).to be_unknown_outcome
      expect(result.observe_before_retry).to be(true)
      expect(result.error_code).to eq("UNKNOWN_OUTCOME")
    end

    it "does not set the flag on an ordinary retryable result" do
      command = ExecutorCommand.new(id: "c", type: "list_nodes", cluster_id: "cl",
        resource_type: "Cluster", resource_id: "self")

      expect(ExecutionResult.retryable(command, "ENGINE_UNAVAILABLE").observe_before_retry).to be(false)
    end

    it "freezes runtime ids and metadata" do
      command = ExecutorCommand.new(id: "c", type: "list_nodes", cluster_id: "cl",
        resource_type: "Cluster", resource_id: "self")
      result = ExecutionResult.applied(command, ids: [ "n1" ], count: 1)

      expect(result.runtime_resource_ids).to be_frozen
      expect(result.safe_metadata).to be_frozen
    end
  end

  # ADR-0009 §3 says the contract spec asserts this, and until M01-18 nothing
  # did: *"An inspect that answers APPLIED with `observed: nil` is a defect"*.
  # It is the assumption every reconciler makes — `inspect_service` is how the
  # diff learns Actual State — and an unasserted assumption is how the network
  # reconciler read `network_data` from a bag nobody wrote for five rounds.
  describe "an inspect that succeeded (ADR-0009 §3)" do
    def scripted(responses)
      client = Class.new do
        def initialize(responses) = @responses = responses
        def get(path)
          key = @responses.keys.find { |k| path.start_with?(k) }
          @responses.fetch(key) { raise "unscripted GET #{path}" }
        end
      end.new(responses)

      info = SwarmBootstrap::Info.new(engine_version: "29.7.2", swarm_state: "active", swarm_id: "a",
        node_id: "n1", manager?: true, node_count: 1, data_root: "/var/lib/docker")
      SwarmExecutor.new(client: client, engine: Class.new { define_singleton_method(:info) { info } },
        logger: instance_double(ActiveSupport::Logger, info: nil))
    end

    def response(status, body)
      EngineClient::Response.new(status: status, body: body, raw: JSON.generate(body))
    end

    let(:service_body) do
      { "ID" => "s1", "Version" => { "Index" => 12 },
        "Spec" => { "Name" => "web", "Labels" => { "com.opanel.service_id" => "svc_1" },
                    "Mode" => { "Replicated" => { "Replicas" => 2 } },
                    "TaskTemplate" => { "ContainerSpec" => { "Image" => "busybox@sha256:abc" } } } }
    end

    it "carries a normalized observation of the kind it inspected" do
      executor = scripted("/services?" => response(200, [ service_body ]),
        "/services/s1" => response(200, service_body))
      command = ExecutorCommand.new(id: "c", type: "inspect_service", cluster_id: "cl",
        resource_type: "Service", resource_id: "svc_1")

      result = executor.execute(command)

      expect(result).to be_applied
      expect(result.observed).to be_a(Opanel::RuntimeObservation)
      expect(result.observed.kind).to eq("service")
      expect(result.observed.runtime_id).to eq("s1")
      expect(result.observed.labels).to include("com.opanel.service_id" => "svc_1")
      expect(result.observed.attributes).to include("image" => "busybox@sha256:abc", "replicas" => 2)
    end

    it "carries none when the inspect failed, because nothing was read" do
      executor = scripted("/services?" => response(200, []))
      command = ExecutorCommand.new(id: "c", type: "inspect_service", cluster_id: "cl",
        resource_type: "Service", resource_id: "svc_1")

      result = executor.execute(command)

      expect(result).to be_failed
      expect(result.observed).to be_nil
    end

    it "keeps the observation out of the metadata bag that reaches the log" do
      executor = scripted("/services?" => response(200, [ service_body ]),
        "/services/s1" => response(200, service_body))
      command = ExecutorCommand.new(id: "c", type: "inspect_service", cluster_id: "cl",
        resource_type: "Service", resource_id: "svc_1")

      result = executor.execute(command)

      expect(result.safe_metadata).not_to have_key(:observed)
      expect(result.safe_metadata.to_s).not_to include("busybox@sha256:abc")
    end
  end
end
