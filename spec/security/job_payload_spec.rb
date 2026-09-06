require "rails_helper"

# A job payload is persisted in PostgreSQL and readable by anything that can read
# the queue tables. It is not a private channel.
RSpec.describe "job payload safety", type: :security do
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  it "refuses to serialize an arbitrary object" do
    arbitrary = Struct.new(:token).new("s3cr3t")

    expect { ExampleCheckpointJob.perform_later(name: arbitrary) }
      .to raise_error(ActiveJob::SerializationError)
  end

  it "refuses to serialize a class reference" do
    expect { ExampleCheckpointJob.perform_later(name: File) }
      .to raise_error(ActiveJob::SerializationError)
  end

  it "never writes job arguments into the log" do
    logs = capture_logs do
      perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "argument-abc123") }
    end

    expect(logs).not_to include("argument-abc123")
    expect(logs).to include("job.performed"), "the execution must still be observable without its arguments"
  end

  it "keeps arguments out of the log when the job fails, too" do
    logs = capture_logs do
      perform_enqueued_jobs { ExampleTransientFailureJob.perform_later(name: "failing-argument-xyz789") }
    rescue ExampleTransientFailureJob::TransientBoom
      nil
    end

    expect(logs).not_to include("failing-argument-xyz789")
    expect(logs).to include("job.failed")
  end

  it "documents in app/jobs/README.md that the broker is not the source of truth" do
    readme = Rails.root.join("app/jobs/README.md").read

    expect(readme).to include("The queue is a delivery mechanism")
    expect(readme).to match(/source of truth/)
    expect(readme).to match(/exactly-once/)
    expect(readme).to match(/Hand off to the Application Layer/)
    expect(readme).to match(/No plaintext secret in a payload/)
  end
end
