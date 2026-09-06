require "rails_helper"

RSpec.describe "asynchronous job baseline", type: :integration do
  include ActiveJob::TestHelper

  # These examples exercise job semantics — retries, discards, idempotency — not
  # the Solid Queue transport. The transport is proven end to end against real
  # workers in spec/integration/worker_crash_spec.rb.
  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  describe "enqueue → execute → observe" do
    it "carries the enqueuing correlation id into the job's own log line" do
      logs = capture_logs do
        Current.set(correlation_id: "corr-enqueue-to-job") do
          perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "observed-run") }
        end
      end

      expect(InfrastructureCheckpoint.find_by(name: "observed-run")).to be_present
      expect(logs).to include("corr-enqueue-to-job")
      expect(logs).to include("job.performed")
      expect(logs).to include("ExampleCheckpointJob")
      expect(logs).to include(Opanel::Queues::SYSTEM)
    end

    it "reports the attempt and the duration of the execution" do
      logs = capture_logs do
        perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "measured-run") }
      end

      expect(logs).to match(/attempt/)
      expect(logs).to match(/duration_ms/)
    end

    it "never writes the job arguments to the log" do
      logs = capture_logs do
        perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "not-in-the-log-abc123") }
      end

      expect(logs).not_to include("not-in-the-log-abc123")
    end
  end

  describe "retry policy" do
    it "retries a transient failure up to the class ceiling and then stops" do
      logs = capture_logs do
        # The last attempt re-raises through the test adapter. The ceiling is what
        # is under test, not the exception's escape route.
        perform_enqueued_jobs { ExampleTransientFailureJob.perform_later(name: "retry-ceiling") }
      rescue ExampleTransientFailureJob::TransientBoom
        nil
      end

      attempts = InfrastructureCheckpoint.find_by(name: "retry-ceiling")&.counter

      expect(attempts).to eq(3), "expected exactly the declared 3 attempts, got #{attempts.inspect}"
      expect(logs).to include("job.failed")
    end

    it "does not retry forever" do
      ceiling = ExampleTransientFailureJob.declared_retry_policy[:attempts]

      expect(ceiling).to be_a(Integer).and be_positive
    end
  end

  describe "payload validation" do
    it "discards an invalid payload without applying any effect" do
      logs = capture_logs do
        expect {
          perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "Not A Valid Name!") }
        }.not_to change(InfrastructureCheckpoint, :count)
      end

      expect(logs).to include("job.discarded_invalid_payload")
    end

    it "rejects an out-of-range argument before doing any work" do
      expect {
        perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "valid-name", hold_seconds: 999) }
      }.not_to change(InfrastructureCheckpoint, :count)
    end

    it "does not retry an invalid payload" do
      logs = capture_logs do
        perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "!!") }
      end

      expect(logs.scan("job.discarded_invalid_payload").length).to eq(1)
    end
  end

  describe "idempotency of the example effect" do
    it "converges instead of duplicating when the same job runs twice" do
      2.times do
        perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "converging") }
      end

      checkpoints = InfrastructureCheckpoint.where(name: "converging")

      expect(checkpoints.count).to eq(1), "the effect was duplicated"
      expect(checkpoints.first.counter).to eq(2), "the execution witness did not record both runs"
    end
  end
end
