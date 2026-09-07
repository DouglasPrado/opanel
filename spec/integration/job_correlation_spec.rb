require "rails_helper"

# HTTP → PostgreSQL → a real worker process.
#
# The round trip in observability_spec proves the payload contract in one
# process. It cannot prove the id survives the *transport*: the queue is a table,
# the worker is another process, and "it worked with the test adapter" is exactly
# the claim that was wrong — `request_id` was never written into the persisted
# payload, so no worker could have recovered it (M00-15 AC2).
RSpec.describe "correlation across the real queue", :solid_queue_worker, type: :integration do
  include RSpec::Rails::RequestExampleGroup
  include InertiaResponse

  # Real processes cannot see rows held open in this process's transaction.
  self.use_transactional_tests = false

  let(:checkpoint_name) { "correlated-#{SecureRandom.hex(4)}" }

  before do
    SolidQueue::Job.destroy_all
    SolidQueue::Process.delete_all
  end

  after do
    InfrastructureCheckpoint.where(name: checkpoint_name).delete_all
    SolidQueue::Job.destroy_all
    SolidQueue::Process.delete_all
  end

  it "writes the request id into the persisted payload and a real worker runs it" do
    get "/", headers: modern_browser
    request_id = response.headers["X-Request-Id"]

    expect(request_id).to be_present, "the HTTP edge generated no request id"

    Current.set(request_id: request_id, correlation_id: request_id) do
      ExampleCheckpointJob.perform_later(name: checkpoint_name)
    end

    enqueued = SolidQueue::Job.find_by(class_name: "ExampleCheckpointJob")

    expect(enqueued).to be_present, "the job never reached the queue table"
    expect(enqueued.arguments["request_id"]).to eq(request_id),
      "the persisted payload lost the request id; a worker cannot recover what was never written"
    expect(enqueued.arguments["correlation_id"]).to eq(request_id)

    start_worker

    wait_until("a real worker to perform the job") do
      InfrastructureCheckpoint.find_by(name: checkpoint_name)
    end
  end
end
