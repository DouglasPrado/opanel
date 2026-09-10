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
      safe_metadata error_code observe_before_retry].freeze

    it "carries the fields §20.2 names, plus the one flag §5.3 requires" do
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
end
