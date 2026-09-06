require "rails_helper"

RSpec.describe Opanel::LogFormatter, type: :unit do
  subject(:formatter) { described_class.new }

  let(:at) { Time.utc(2026, 9, 6, 12, 30, 45, 123_000) }

  def line(message, severity: "INFO", progname: nil)
    JSON.parse(formatter.call(severity, at, progname, message))
  end

  describe "the shape of a line" do
    it "is one JSON object per line" do
      output = formatter.call("INFO", at, nil, "service converged")

      expect(output).to end_with("\n")
      expect(output.count("\n")).to eq(1)
      expect { JSON.parse(output) }.not_to raise_error
    end

    it "carries the mandatory fields" do
      expect(line("service converged")).to include(
        "timestamp" => "2026-09-06T12:30:45.123Z",
        "level" => "info",
        "message" => "service converged",
        "source" => "opanel"
      )
    end

    it "records the timestamp in UTC" do
      expect(line("x")["timestamp"]).to end_with("Z")
    end

    it "turns a Hash message into fields rather than an inspected string" do
      entry = line({ event: "job.performed", queue: "system", attempt: 1 })

      expect(entry).to include("event" => "job.performed", "queue" => "system", "attempt" => 1)
      expect(entry).not_to have_key("message")
    end

    it "records an exception by class and message" do
      entry = line(ActiveRecord::RecordNotUnique.new("duplicate key"))

      expect(entry).to include("message" => "duplicate key", "error_class" => "ActiveRecord::RecordNotUnique")
    end
  end

  describe "correlation" do
    it "attaches the request and correlation ids from Current" do
      Current.set(request_id: "req-1", correlation_id: "corr-1") do
        expect(line("x")).to include("request_id" => "req-1", "correlation_id" => "corr-1")
      end
    end

    it "omits a correlation field nobody set, rather than emitting a null" do
      Current.set(request_id: nil, correlation_id: "corr-1") do
        expect(line("x")).not_to have_key("request_id")
        expect(line("x")).not_to have_key("team_id")
      end
    end

    # The point of declaring these now: the Milestones that own them start
    # setting them and nothing about the formatter changes.
    it "carries every reserved field without a change of signature" do
      reserved = {
        operation_id: "op-1", team_id: "team-1", project_id: "prj-1",
        environment_id: "env-1", service_id: "svc-1", cluster_id: "cl-1",
        node_id: "node-1", actor_id: "usr-1"
      }

      Current.set(**reserved) do
        entry = line("x")

        reserved.each_key { |field| expect(entry[field.to_s]).to eq(reserved[field]) }
      end
    end

    it "declares the reserved fields Annex I §19.2 requires" do
      expect(described_class::CORRELATION_FIELDS).to include(
        :request_id, :operation_id, :team_id, :project_id,
        :environment_id, :service_id, :cluster_id, :node_id, :actor_id, :source
      )
    end
  end

  describe "redaction at the sink" do
    it "masks a value whose field name says it is a secret" do
      entry = line({ event: "provider.configured", password: "hunter2", api_key: "opk_123456" })

      expect(entry["password"]).to eq(Opanel::Redaction::MASK)
      expect(entry["api_key"]).to eq(Opanel::Redaction::MASK)
      expect(formatter.call("INFO", at, nil, { password: "hunter2" })).not_to include("hunter2")
    end

    it "masks a credential shape in free text" do
      entry = line("connecting to postgres://opanel:s3cr3t@db:5432/opanel")

      expect(entry["message"]).not_to include("s3cr3t")
      expect(entry["message"]).to include(Opanel::Redaction::MASK)
    end

    it "masks an authorization header however it reached the line" do
      entry = line("rejected request with authorization: Bearer abcdef0123456789")

      expect(entry["message"]).not_to include("abcdef0123456789")
    end

    it "masks a private key block" do
      entry = line("key material: -----BEGIN RSA PRIVATE KEY-----\nMIIEpAIB\n-----END RSA PRIVATE KEY-----")

      expect(entry["message"]).not_to include("MIIEpAIB")
    end

    it "masks a nested value inside a Hash message" do
      entry = line({ event: "operation.enqueued", payload: { service_id: "svc-1", token: "tok_abcdef123456" } })

      expect(entry.dig("payload", "token")).to eq(Opanel::Redaction::MASK)
      expect(entry.dig("payload", "service_id")).to eq("svc-1")
    end

    it "leaves an ordinary message alone" do
      expect(line("converged 3/3 tasks")["message"]).to eq("converged 3/3 tasks")
    end
  end

  describe "when formatting itself fails" do
    it "still emits a line, and says the formatter failed" do
      unserializable = Object.new
      def unserializable.to_s = raise(IOError, "cannot render")

      output = formatter.call("ERROR", at, nil, unserializable)

      expect(output).to end_with("\n")
      expect(output).to include("log_formatter_error").or include("ERROR")
    end
  end
end
