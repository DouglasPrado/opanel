require "rails_helper"

# The transport, with `curl` stood in for. The real socket is exercised in
# `spec/integration/swarm_executor_lab_spec.rb`; what is tested here is the one
# thing a live daemon cannot be asked to do — fail in each distinct way — and the
# shape of the command line that reaches it.
RSpec.describe EngineClient, type: :unit do
  subject(:client) { described_class.new(socket: "/tmp/docker.sock") }

  def curl_answers(stdout: "", stderr: "", exit_code: 0)
    status = instance_double(Process::Status, success?: exit_code.zero?, exitstatus: exit_code)
    allow(Open3).to receive(:capture3) do |*args, **options|
      @curl_args = args
      @curl_stdin = options[:stdin_data]
      [ stdout, stderr, status ]
    end
  end

  describe "the request it builds" do
    it "speaks to the unix socket, and to nothing else" do
      curl_answers(stdout: "{}\n200")

      client.get("/info")

      expect(@curl_args.first).to eq("curl")
      expect(@curl_args).to include("--unix-socket", "/tmp/docker.sock")
      expect(@curl_args.last).to eq("http://localhost/#{described_class::API_VERSION}/info")
      expect(@curl_args.join(" ")).not_to match(/tcp:|2375|2376/)
    end

    it "pins the API version rather than negotiating per call" do
      curl_answers(stdout: "{}\n200")

      client.get("/version")

      expect(@curl_args.last).to start_with("http://localhost/v1.44/")
    end

    it "bounds both the connect and the transfer" do
      curl_answers(stdout: "{}\n200")

      client.get("/info")

      expect(@curl_args).to include("--connect-timeout", "--max-time")
    end

    it "sends a JSON body on the standard input, never on the command line" do
      curl_answers(stdout: "{\"ID\":\"s1\"}\n201")

      client.post("/services/create", { "Name" => "web" })

      expect(@curl_args).to include("--data-binary", "@-")
      expect(@curl_stdin).to eq('{"Name":"web"}')
      expect(@curl_args.join(" ")).not_to include("web")
    end
  end

  describe "the answer it parses" do
    it "separates the status from the body" do
      curl_answers(stdout: "{\"ID\":\"s1\"}\n201")

      response = client.get("/x")

      expect(response.status).to eq(201)
      expect(response.body).to eq("ID" => "s1")
      expect(response).to be_ok
    end

    it "keeps a non-JSON body raw, for logs and pings" do
      curl_answers(stdout: "OK\n200")

      response = client.get("/_ping")

      expect(response.body).to be_nil
      expect(response.raw).to eq("OK")
    end

    it "exposes the Engine's message for classification" do
      curl_answers(stdout: "{\"message\":\"update out of sequence\"}\n500")

      expect(client.get("/x").message).to eq("update out of sequence")
    end

    it "refuses an answer with no status rather than guessing" do
      curl_answers(stdout: "")

      expect { client.get("/x") }.to raise_error(described_class::Error, /no HTTP status/)
    end
  end

  # doc 07 §5.3's one distinction that matters: could the daemon have acted?
  describe "transport failures" do
    it "classifies a refused connection as transient" do
      curl_answers(stderr: "curl: (7) Failed to connect", exit_code: 7)

      expect { client.post("/services/create", {}) }
        .to raise_error(described_class::Error) { |e| expect(e).to be_transient }
    end

    it "classifies a timeout on a GET as transient — nothing was mutated" do
      curl_answers(stderr: "curl: (28) Operation timed out after 20000 milliseconds", exit_code: 28)

      expect { client.get("/services/s1") }
        .to raise_error(described_class::Error) { |e| expect(e).to be_transient }
    end

    # The daemon was reached and the answer never came back: it may have applied
    # the mutation. This is the case that must not be retried blindly.
    it "classifies a transfer timeout on a mutation as unknown outcome" do
      curl_answers(stderr: "curl: (28) Operation timed out after 20000 milliseconds with 0 bytes received",
exit_code: 28)

      expect { client.post("/services/create", {}) }
        .to raise_error(described_class::Error) { |e| expect(e).to be_unknown_outcome }
    end

    # There is no "connect timeout on a mutation is transient" example any more.
    # The review reproduced both a stalled connect and a stalled transfer against
    # a real unix socket and curl reported the same message for both, so the
    # distinction the first version drew was between a string curl emits and one
    # it does not. Any timeout on a mutating verb is unknown — the only answer
    # this side of the socket can give honestly.
    it "classifies every timeout on a mutation as unknown, whatever curl says" do
      curl_answers(stderr: "curl: (28) Connection timed out after 5000 milliseconds", exit_code: 28)

      expect { client.post("/services/create", {}) }
        .to raise_error(described_class::Error) { |e| expect(e).to be_unknown_outcome }
    end

    it "classifies a missing curl as transient rather than crashing" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { client.get("/x") }.to raise_error(described_class::Error, /curl is not on PATH/)
    end
  end

  describe "the socket" do
    it "is resolved from the daemon's own endpoint when not given" do
      allow(SwarmBootstrap).to receive(:endpoint).and_return("unix:///var/run/docker.sock")

      expect(described_class.new.socket).to eq("/var/run/docker.sock")
    end

    # AC8 of M01-08 again, from this side: a TCP endpoint is not a socket, and
    # the client will not dial one.
    it "refuses an endpoint that is not a unix socket" do
      allow(SwarmBootstrap).to receive(:endpoint).and_return("tcp://192.0.2.1:2376")

      expect { described_class.new.socket }.to raise_error(described_class::Error, /not a unix socket/)
    end
  end
end
