require "rails_helper"

RSpec.describe ApplicationJob, type: :unit do
  describe "retry policy" do
    it "is declared per class, never inherited as a blind global default" do
      expect(described_class.declared_retry_policy).to be_nil
    end

    it "records what the class declared" do
      policy = ExampleTransientFailureJob.declared_retry_policy

      expect(policy[:on]).to eq([ ExampleTransientFailureJob::TransientBoom ])
      expect(policy[:attempts]).to eq(3)
    end

    it "lets two job classes hold different policies" do
      expect(ExampleCheckpointJob.declared_retry_policy[:on])
        .not_to eq(ExampleTransientFailureJob.declared_retry_policy[:on])
    end

    it "refuses an unbounded retry policy" do
      job_class = Class.new(described_class)

      expect { job_class.retry_policy(on: StandardError, attempts: 0) }
        .to raise_error(ArgumentError, /positive integer/)
      expect { job_class.retry_policy(on: StandardError, attempts: nil) }
        .to raise_error(ArgumentError, /positive integer/)
    end
  end

  describe "correlation id" do
    it "captures the enqueuing context into the serialized payload" do
      Current.set(correlation_id: "corr-from-request") do
        payload = ExampleCheckpointJob.new(name: "example").serialize

        expect(payload["correlation_id"]).to eq("corr-from-request")
      end
    end

    it "restores the captured id when the payload is deserialized" do
      serialized = Current.set(correlation_id: "corr-abc") do
        ExampleCheckpointJob.new(name: "example").serialize
      end

      restored = ActiveJob::Base.deserialize(serialized)

      expect(restored.correlation_id).to eq("corr-abc")
    end

    it "generates one when nobody set it, so a log line is never uncorrelatable" do
      Current.set(correlation_id: nil) do
        expect(ExampleCheckpointJob.new(name: "example").correlation_id).to be_present
      end
    end
  end
end
