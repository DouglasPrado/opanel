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

  describe "request id" do
    it "captures the enqueuing request into the serialized payload" do
      Current.set(request_id: "req-from-edge") do
        payload = ExampleCheckpointJob.new(name: "example").serialize

        expect(payload["request_id"]).to eq("req-from-edge")
      end
    end

    it "restores it when the payload is deserialized" do
      serialized = Current.set(request_id: "req-abc") do
        ExampleCheckpointJob.new(name: "example").serialize
      end

      restored = ActiveJob::Base.deserialize(serialized)

      expect(restored.request_id).to eq("req-abc")
    end

    # The opposite of the correlation id, and deliberately so: a job nobody
    # requested has none, and inventing one would claim a request that never
    # happened.
    it "is nil when no request enqueued the job" do
      Current.set(request_id: nil) do
        expect(ExampleCheckpointJob.new(name: "example").request_id).to be_nil
      end
    end

    it "does not re-read Current after it was captured" do
      job = Current.set(request_id: "req-first") { ExampleCheckpointJob.new(name: "example").tap(&:request_id) }

      Current.set(request_id: "req-second") do
        expect(job.request_id).to eq("req-first")
      end
    end
  end
end
