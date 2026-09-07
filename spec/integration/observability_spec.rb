require "rails_helper"

# The base observability contract: a failure has to be diagnosable from the log
# without reproducing it (Annex I §19.2). That means the id a user can quote is
# the same id in the controller's log line, in the job that request enqueued, and
# in the error page they were shown.
RSpec.describe "observability", type: :integration do
  include ActiveJob::TestHelper
  include RSpec::Rails::RequestExampleGroup
  include InertiaResponse

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def json_lines(output)
    output.lines.filter_map do |raw|
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end

  describe "request → log" do
    it "logs in JSON with the mandatory fields" do
      logs = capture_logs { get "/", headers: modern_browser }
      entries = json_lines(logs)

      expect(entries).not_to be_empty, "the application logged nothing parseable:\n#{logs}"
      entries.each do |entry|
        expect(entry).to include("timestamp", "level", "source")
      end
    end

    it "carries the request id into every line the request produced" do
      logs = capture_logs { get "/", headers: modern_browser }
      request_id = response.headers["X-Request-Id"]

      correlated = json_lines(logs).select { |entry| entry["request_id"] == request_id }

      expect(correlated).not_to be_empty,
        "no log line carried the request id #{request_id}; the response cannot be traced"
    end
  end

  describe "request → job" do
    # This is the property the whole correlation contract exists for: the work a
    # request scheduled is findable from the id the user was shown.
    #
    # Enqueuing and performing inside one `Current` proves nothing — it passes
    # with no serialization at all, which is how `request_id` came to be dropped
    # by the queue and stay dropped through a green suite. So the payload is
    # serialized, `Current` is reset the way a worker process starts, and the job
    # is executed through the same entry point a worker uses.
    it "propagates the request id into the job the request enqueued" do
      get "/", headers: modern_browser
      request_id = response.headers["X-Request-Id"]

      payload = Current.set(request_id: request_id, correlation_id: request_id) do
        ExampleCheckpointJob.new(name: "correlated-run").serialize
      end

      Current.reset

      logs = capture_logs { ActiveJob::Base.execute(payload) }
      job_line = json_lines(logs).find { |entry| entry["event"] == "job.performed" }

      expect(job_line).not_to be_nil, "the job did not log its execution"
      expect(job_line["request_id"]).to eq(request_id),
        "the job's log line cannot be traced back to the request that scheduled it"
      expect(job_line["correlation_id"]).to eq(request_id)
    end

    it "leaves the request id out when no request enqueued the job" do
      Current.reset

      payload = ExampleCheckpointJob.new(name: "unrequested-run").serialize
      logs = capture_logs { ActiveJob::Base.execute(payload) }
      job_line = json_lines(logs).find { |entry| entry["event"] == "job.performed" }

      expect(job_line).not_to be_nil
      expect(job_line["request_id"]).to be_nil,
        "a job nobody requested must not borrow another request's id"
      expect(job_line["correlation_id"]).to be_present
    end

    it "gives a job with no enqueuing request a correlation id of its own" do
      logs = capture_logs do
        Current.set(correlation_id: nil) do
          perform_enqueued_jobs { ExampleCheckpointJob.perform_later(name: "uncorrelated-run") }
        end
      end

      job_line = json_lines(logs).find { |entry| entry["event"] == "job.performed" }

      expect(job_line["correlation_id"]).to be_present,
        "a log line that cannot be correlated is a log line nobody can use"
    end
  end

  describe "a user-visible error" do
    around do |example|
      config = Rails.application.env_config
      previous = config.values_at("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
      config["action_dispatch.show_exceptions"] = :all
      config["action_dispatch.show_detailed_exceptions"] = false
      example.run
    ensure
      config["action_dispatch.show_exceptions"] = previous[0]
      config["action_dispatch.show_detailed_exceptions"] = previous[1]
    end

    # The id on the screen has to be the id in the log, or quoting it achieves
    # nothing (doc 09 §28).
    it "shows the same request id the response header carries" do
      get "/this-route-does-not-exist", headers: modern_browser

      expect(response).to have_http_status(:not_found)
      expect(inertia_props["requestId"]).to eq(response.headers["X-Request-Id"])
    end

    it "carries no stack trace, SQL or internal path" do
      get "/this-route-does-not-exist", headers: modern_browser

      expect(response.body).not_to match(/ActionController::RoutingError/)
      expect(response.body).not_to match(%r{/app/controllers/})
      expect(response.body).not_to match(/SELECT .* FROM/i)
    end
  end

  describe "redaction at the sink" do
    it "masks a secret planted in a log message" do
      logs = capture_logs { Rails.logger.info("provider responded with token=tok_abcdef123456") }

      expect(logs).not_to include("tok_abcdef123456")
      expect(logs).to include(Opanel::Redaction::MASK)
    end

    it "never writes an authorization header or a cookie" do
      logs = capture_logs do
        get "/", headers: modern_browser.merge(
          "HTTP_AUTHORIZATION" => "Bearer probe-token-abc123",
          "HTTP_COOKIE" => "_opanel_session=probe-session-xyz789"
        )
      end

      expect(logs).not_to include("probe-token-abc123")
      expect(logs).not_to include("probe-session-xyz789")
    end
  end
end
