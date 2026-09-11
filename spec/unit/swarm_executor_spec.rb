require "rails_helper"

# The executor's decisions, with the Engine stood in for.
#
# The Engine itself is exercised for real in `spec/integration/swarm_executor_lab_spec.rb`.
# What is tested here is everything a real daemon cannot be asked to do on
# demand: answer 503, lose a reply, be a worker, return a 500 that is a conflict
# and a 500 that is not. The stand-ins are plain objects with the same methods —
# a mock agrees with whatever the code believes, and the belief is what is under
# test.
RSpec.describe SwarmExecutor, type: :unit do
  # A scripted Engine API: `responses` maps "METHOD path" (path matched as a
  # prefix) to a Response or an EngineClient::Error to raise. Records every call.
  class ScriptedClient
    attr_reader :calls

    def initialize(responses = {})
      @responses = responses
      @calls = []
    end

    def get(path) = answer("GET", path)
    def post(path, body = nil) = answer("POST", path, body)
    def delete(path) = answer("DELETE", path)

    private

    def answer(method, path, body = nil)
      @calls << [ method, path, body ]
      key = @responses.keys.find { |k| k.start_with?("#{method} ") && path.start_with?(k.split(" ", 2).last) }
      raise "unscripted #{method} #{path}" if key.nil?

      value = @responses[key]
      value = value.call if value.respond_to?(:call)
      raise value if value.is_a?(StandardError)

      value
    end
  end

  # A bare `"ID" => "s1"` after the status arrives as keywords in Ruby 3; both
  # spellings are accepted so the examples read like the Engine's own JSON.
  def response(status, body = nil, raw: nil, **keyword_body)
    body = keyword_body.transform_keys(&:to_s) if body.nil? && !keyword_body.empty?
    EngineClient::Response.new(status: status, body: body, raw: raw || (body ? JSON.generate(body) : ""))
  end

  def engine(manager: true)
    info = SwarmBootstrap::Info.new(engine_version: "29.7.2", swarm_state: "active", swarm_id: "abc",
      node_id: "node1", manager?: manager, node_count: 1, data_root: "/var/lib/docker")
    Class.new { define_singleton_method(:info) { info } }
  end

  def command(type, id: "svc_1", **payload)
    ExecutorCommand.new(id: "cmd_#{type}", type: type, cluster_id: "cl_1", resource_type: "Service",
      resource_id: id, correlation_id: "corr_1", payload: payload)
  end

  let(:logger) { instance_double(ActiveSupport::Logger, info: nil) }

  # Same Ruby-3 rule as `response`: a bare `"GET /x" => …` arrives as keywords.
  def executor(responses = {}, manager: true, **scripted)
    client = ScriptedClient.new(responses.merge(scripted.transform_keys(&:to_s)))
    described_class.new(client: client, engine: engine(manager: manager), logger: logger)
  end

  SERVICE = {
    "ID" => "s1", "Version" => { "Index" => 12 },
    "Spec" => { "Name" => "web", "Labels" => {},
                "TaskTemplate" => { "ContainerSpec" => { "Image" => "img" } } }
  }.freeze

  describe "the allowlist (AC3, AC4)" do
    it "declares exactly the operations M01 needs" do
      expect(described_class::OPERATIONS.keys).to match_array(%w[
        inspect_service create_service update_service_spec remove_service
        create_network inspect_network remove_network list_nodes inspect_node
        service_logs list_tasks
      ])
    end

    it "refuses a type outside it before touching the Engine" do
      client = ScriptedClient.new
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect { ex.execute(command("exec_command")) }
        .to raise_error(ExecutorCommand::Invalid, /not an executor operation/)
      expect(client.calls).to be_empty
    end

    it "refuses a payload key outside the operation's allowlist before touching the Engine" do
      client = ScriptedClient.new
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect { ex.execute(command("create_service", image: "img", mounts: [ "/:/host" ])) }
        .to raise_error(ExecutorCommand::Invalid, /mounts/)
      expect(client.calls).to be_empty
    end

    # An id is interpolated into a URL. Anything that is not an id is a way to
    # reach a path the allowlist never named.
    it "refuses a resource id that is not a runtime identifier" do
      client = ScriptedClient.new
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect { ex.execute(command("inspect_service", id: "s1/../../networks?x=1")) }
        .to raise_error(ExecutorCommand::Invalid, /not a runtime identifier/)
      expect(client.calls).to be_empty
    end
  end

  # AC11: a payload is a thing that gets logged and persisted. Secret material is
  # refused by key, at every depth, before any call.
  describe "secret material in a payload (AC11)" do
    it "refuses a sensitive key under an allowed one" do
      ex = executor
      expect { ex.execute(command("create_service", image: "img", labels: { "registry_password" => "hunter2" })) }
        .to raise_error(ExecutorCommand::Invalid, /labels\.registry_password/)
    end

    it "accepts a SecretVersion reference, which is the shape doc 07 §21 wants" do
      ex = executor("GET /services?" => response(200, []),
        "POST /services/create" => response(201, "ID" => "s1"),
        "GET /services/s1" => response(200, SERVICE))

      result = ex.execute(command("create_service", image: "img", env: [ "SECRET_REF=sv_01HX" ]))

      expect(result).to be_applied
    end
  end

  describe "the Manager guard (AC9)" do
    it "refuses, closed, on a worker — and never reaches the Engine" do
      client = ScriptedClient.new
      ex = described_class.new(client: client, engine: engine(manager: false), logger: logger)

      result = ex.execute(command("list_nodes", id: "self"))

      expect(result).to be_failed
      expect(result.error_code).to eq(ExecutionResult::NOT_A_MANAGER)
      expect(client.calls).to be_empty
    end

    it "reads the role from the daemon on every call, so a demotion takes effect at once" do
      info = engine(manager: true)
      ex = described_class.new(client: ScriptedClient.new("GET /nodes" => response(200, [])), engine: info,
logger: logger)
      expect(ex.execute(command("list_nodes", id: "self"))).to be_applied

      demoted = engine(manager: false)
      ex2 = described_class.new(client: ScriptedClient.new, engine: demoted, logger: logger)
      expect(ex2.execute(command("list_nodes", id: "self")).error_code).to eq(ExecutionResult::NOT_A_MANAGER)
    end

    it "answers RETRYABLE when the daemon cannot say what it is" do
      down = Class.new { def self.info
                           raise(SwarmBootstrap::EngineError.new(SwarmBootstrap::DAEMON_UNREACHABLE, "x"))
                         end }
      ex = described_class.new(client: ScriptedClient.new, engine: down, logger: logger)

      result = ex.execute(command("list_nodes", id: "self"))

      expect(result).to be_retryable
      expect(result.error_code).to eq(ExecutionResult::ENGINE_UNAVAILABLE)
    end
  end

  # AC5 — doc 07 §5.3 onto doc 09 §28, one line each.
  describe "error classification (AC5)" do
    def result_for(status, body = nil)
      # ADR-0009 §5: address by label filter first, then use the runtime ID
      executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(status, body)).execute(command("inspect_service"))
    end

    it "400 → FAILED VALIDATION_ERROR" do
      expect(result_for(400, "message" => "bad")).to have_attributes(outcome: "FAILED", error_code: "VALIDATION_ERROR")
    end

    it "404 on an inspect → FAILED NOT_FOUND" do
      expect(result_for(404,
"message" => "no such service")).to have_attributes(outcome: "FAILED", error_code: "NOT_FOUND")
    end

    it "409 → CONFLICT" do
      expect(result_for(409, "message" => "name conflicts")).to be_conflict
    end

    # The Engine answers a stale-version update with **500**, not 409 — proved
    # against the lab. The message is what says it is a conflict.
    it "500 'update out of sequence' → CONFLICT" do
      ex = executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE),
        "POST /services/s1/update" => response(500,
"message" => "rpc error: code = Unknown desc = update out of sequence"))

      result = ex.execute(command("update_service_spec", replicas: 2, version: 11))

      expect(result).to be_conflict
      expect(result.error_code).to eq("CONFLICT")
    end

    it "any other 500 → FAILED RUNTIME_REJECTED, never CONFLICT" do
      expect(result_for(500,
"message" => "something else")).to have_attributes(outcome: "FAILED", error_code: "RUNTIME_REJECTED")
    end

    it "503 → RETRYABLE ENGINE_UNAVAILABLE" do
      expect(result_for(503)).to have_attributes(outcome: "RETRYABLE", error_code: "ENGINE_UNAVAILABLE")
    end

    it "a transport failure before the daemon could act → RETRYABLE" do
      ex = executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => EngineClient::Error.new(:transient, "could not connect"))

      result = ex.execute(command("inspect_service"))

      expect(result).to be_retryable
      expect(result).not_to be_unknown_outcome
    end
  end

  # AC6 — a lost answer is not a failure, and it is not resent blindly.
  describe "an unknown outcome (AC6)" do
    let(:lost) { EngineClient::Error.new(:unknown, "the Engine did not answer a POST in 20s; it may have applied it") }

    it "is reported as unknown, never as FAILED" do
      ex = executor("GET /services?" => response(200, []), "POST /services/create" => lost)

      result = ex.execute(command("create_service", image: "img"))

      expect(result).to be_unknown_outcome
      expect(result).not_to be_failed
      expect(result.observe_before_retry).to be(true)
    end

    it "retry_after_observing answers NOOP when the runtime already shows the effect, without resending" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE))
      ex = described_class.new(client: client, engine: engine, logger: logger)

      result = ex.retry_after_observing(command("create_service", image: "img"))

      expect(result).to be_noop
      expect(result.safe_metadata[:reobserved]).to be(true)
      expect(client.calls.map(&:first)).to eq([ "GET", "GET" ])
    end

    it "retry_after_observing applies once more only when the observation shows nothing" do
      client = ScriptedClient.new(
        "GET /services?" => response(200, []),
        "POST /services/create" => response(201, "ID" => "s1"),
        "GET /services/s1" => response(200, SERVICE)
      )
      ex = described_class.new(client: client, engine: engine, logger: logger)

      result = ex.retry_after_observing(command("create_service", image: "img"))

      expect(result).to be_applied
      # Observed first (by label filter), then created — never created first.
      expect(client.calls.map { |m, p, _| "#{m} #{p}" }.first).to match(%r{GET /services\?})
    end

    it "retry_after_observing treats an absent resource as converged for a remove" do
      client = ScriptedClient.new("GET /services?" => response(200, []))
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect(ex.retry_after_observing(command("remove_service"))).to be_noop
      expect(client.calls.length).to eq(1)
    end
  end

  # AC7 and AC8 — idempotent by construction.
  describe "idempotency" do
    it "adopts a service already carrying the platform label instead of creating another (AC7)" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]))
      ex = described_class.new(client: client, engine: engine, logger: logger)

      result = ex.execute(command("create_service", image: "img"))

      expect(result).to be_noop
      expect(result.safe_metadata[:adopted]).to be(true)
      expect(result.runtime_resource_ids).to eq([ "s1" ])
      expect(client.calls.map(&:first)).not_to include("POST")
    end

    # Review L-1 (round 2): the guard in `find_by_label` was real and untested —
    # reverting it failed nothing. A create with an id that is not a runtime
    # identifier must be refused before the label lookup, with no call made.
    it "refuses to look up by a resource id that is not a runtime identifier, before any call" do
      client = ScriptedClient.new("GET /services?" => response(200, []))
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect { ex.execute(command("create_service", id: "svc/../networks?x=1", image: "img")) }
        .to raise_error(ExecutorCommand::Invalid, /not a runtime identifier/)
      expect(client.calls).to be_empty
    end

    it "looks up by the ownership label (service_id), not by name" do
      client = ScriptedClient.new("GET /services?" => response(200, []),
        "POST /services/create" => response(201, "ID" => "s1"), "GET /services/s1" => response(200, SERVICE))
      described_class.new(client: client, engine: engine,
logger: logger).execute(command("create_service", image: "img"))

      lookup = client.calls.first.last(2).first
      expect(CGI.unescape(lookup)).to include(%(com.opanel.service_id=svc_1))
    end

    it "stamps the created service with ownership labels" do
      client = ScriptedClient.new("GET /services?" => response(200, []),
        "POST /services/create" => response(201, "ID" => "s1"), "GET /services/s1" => response(200, SERVICE))
      described_class.new(client: client, engine: engine,
logger: logger).execute(command("create_service", image: "img"))

      body = client.calls.find { |m, _, _| m == "POST" }.last
      # Executor receives labels from payload; this test verifies they're passed through
      # (the actual label set is created by Opanel::Ownership in the application layer)
      expect(body["Labels"]).to be_a(Hash)
    end

    it "treats removing an absent service as converged (AC8)" do
      # ADR-0009 §5: find_by_label is called first, and returns nil when the service does not exist
      result = executor("GET /services?" => response(200, [])).execute(command("remove_service"))

      expect(result).to be_noop
      expect(result.safe_metadata[:absent]).to be(true)
    end

    it "treats removing a service that no longer exists in the Swarm as converged" do
      # If found by label but deleted via DELETE, also converged
      # ADR-0009 §5: find_by_label returns the service, but DELETE returns 404
      service_response = response(200,
[ { "ID" => "s1", "Spec" => { "Labels" => { "com.opanel.service_id" => "svc_1" } } } ])
      result = executor("GET /services?" => service_response,
        "DELETE /services/s1" => response(404)).execute(command("remove_service"))

      expect(result).to be_noop
      expect(result.safe_metadata[:absent]).to be(true)
    end

    it "treats removing an absent network as converged (AC8)" do
      result = executor("GET /networks?" => response(200, []),
        "DELETE /networks/net_1" => response(404)).execute(command("remove_network", id: "net_1"))

      expect(result).to be_noop
    end
  end

  describe "update_service_spec" do
    # Review H-1. The first version substituted the index it had just read when
    # the caller sent none — a blind read-modify-write, the CLI hazard the
    # transport exists to avoid — and this example encoded it as expected. Now an
    # update with no baseline is refused, and nothing is sent.
    it "refuses an update that carries no observed version, and sends nothing" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE),
        "POST /services/s1/update" => response(200, {}))
      ex = described_class.new(client: client, engine: engine, logger: logger)

      expect { ex.execute(command("update_service_spec", replicas: 3)) }
        .to raise_error(ExecutorCommand::Invalid, /observed/)
      expect(client.calls.map(&:first)).not_to include("POST")
    end

    it "sends the version the caller observed, and the merged spec" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE),
        "POST /services/s1/update" => response(200, {}))
      described_class.new(client: client, engine: engine, logger: logger)
        .execute(command("update_service_spec", replicas: 3, version: 12))

      update = client.calls.find { |m, p, _| m == "POST" }
      expect(update[1]).to end_with("?version=12")
      expect(update[2]["Mode"]).to eq("Replicated" => { "Replicas" => 3 })
    end

    it "sends the version the command carries when it does" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE),
        "POST /services/s1/update" => response(200, {}))
      described_class.new(client: client, engine: engine,
logger: logger).execute(command("update_service_spec", replicas: 3, version: 7))

      expect(client.calls.find { |m, _, _| m == "POST" }[1]).to end_with("?version=7")
    end

    it "applies a revision over the current spec rather than a blank one" do
      client = ScriptedClient.new("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE),
        "POST /services/s1/update" => response(200, {}))
      described_class.new(client: client, engine: engine, logger: logger)
        .execute(command("update_service_spec", replicas: 3, version: 12))

      body = client.calls.find { |m, _, _| m == "POST" }.last
      expect(body.dig("TaskTemplate", "ContainerSpec", "Image")).to eq("img")
      expect(body["Name"]).to eq("web")
    end
  end

  # M01-18, DECISIONS.md item (c): `service_logs` and `list_tasks` used to
  # interpolate `resource_id` straight into the Engine path, so the external
  # `svc_…` their own contract mandates (ADR-0009 §5) reached `/services/svc_…`
  # and 404'd. They now find the runtime id by ownership label, like their
  # create and inspect twins. M01-18 is `list_tasks`'s first production caller.
  describe "addressing by ownership label (ADR-0009 §5)" do
    OWNED = [ { "ID" => "s1", "Spec" => { "Labels" => { "com.opanel.service_id" => "svc_1" } } } ].freeze

    def log_frame(text)
      ([ 1, 0, 0, 0 ].pack("C4") + [ text.bytesize ].pack("N") + text).b
    end

    describe "service_logs" do
      it "reads the logs of the runtime id the label lookup returned" do
        client = ScriptedClient.new("GET /services?" => response(200, OWNED),
          "GET /services/s1/logs" => response(200, nil, raw: log_frame("hello-from-lab\n")))
        result = described_class.new(client: client, engine: engine, logger: logger)
          .execute(command("service_logs", tail: 5))

        expect(result).to be_applied
        expect(result.safe_metadata[:lines]).to include("hello-from-lab")
        expect(client.calls.map { |_, path, _| path }).to include(a_string_starting_with("/services/s1/logs"))
      end

      it "answers NOT_FOUND when no service carries the label, and asks the daemon for no path" do
        client = ScriptedClient.new("GET /services?" => response(200, []))
        result = described_class.new(client: client, engine: engine, logger: logger)
          .execute(command("service_logs"))

        expect(result).to be_failed
        expect(result.error_code).to eq("NOT_FOUND")
        expect(client.calls.map { |_, path, _| path }).to all(start_with("/services?"))
      end
    end

    describe "list_tasks" do
      it "filters tasks by the runtime id the label lookup returned, never by the external id" do
        client = ScriptedClient.new("GET /services?" => response(200, OWNED),
          "GET /tasks?" => response(200, [ { "ID" => "t1", "Status" => { "State" => "running" } } ]))
        result = described_class.new(client: client, engine: engine, logger: logger)
          .execute(command("list_tasks"))

        expect(result).to be_applied
        expect(result.safe_metadata[:count]).to eq(1)
        filter = CGI.unescape(client.calls.last[1])
        expect(filter).to include("s1")
        expect(filter).not_to include("svc_1")
      end

      it "answers NOT_FOUND when no service carries the label" do
        client = ScriptedClient.new("GET /services?" => response(200, []))
        result = described_class.new(client: client, engine: engine, logger: logger)
          .execute(command("list_tasks"))

        expect(result).to be_failed
        expect(result.error_code).to eq("NOT_FOUND")
      end
    end

    # M01-18 AC9. The daemon accepts a create it cannot schedule (verified
    # against Engine 29.7.2: an unsatisfiable constraint and a nonexistent
    # digest both answer 201), so "BLOCKED with an observable cause" can only
    # come from the tasks. The executor classifies; it never carries the
    # daemon's message, because `ExecutionResult` says that bag holds no body.
    describe "the blocking classification of tasks" do
      def tasks_answering(state, err)
        ScriptedClient.new("GET /services?" => response(200, OWNED),
          "GET /tasks?" => response(200, [ { "ID" => "t1", "Status" => { "State" => state, "Err" => err } } ]))
      end

      it "classifies an unschedulable task as PLACEMENT_IMPOSSIBLE" do
        client = tasks_answering("pending", "no suitable node (scheduling constraints not satisfied on 1 node)")
        result = described_class.new(client: client, engine: engine, logger: logger).execute(command("list_tasks"))

        expect(result.safe_metadata[:blocking_code]).to eq("PLACEMENT_IMPOSSIBLE")
      end

      it "classifies an unresolvable image as IMAGE_UNAVAILABLE" do
        client = tasks_answering("rejected",
          %(failed to resolve reference "docker.io/library/busybox@sha256:0000": not found))
        result = described_class.new(client: client, engine: engine, logger: logger).execute(command("list_tasks"))

        expect(result.safe_metadata[:blocking_code]).to eq("IMAGE_UNAVAILABLE")
      end

      it "carries no blocking code when the tasks are running" do
        client = tasks_answering("running", nil)
        result = described_class.new(client: client, engine: engine, logger: logger).execute(command("list_tasks"))

        expect(result.safe_metadata).not_to have_key(:blocking_code)
      end

      it "never carries the daemon's own message into the metadata bag" do
        planted = "no suitable node (scheduling constraints not satisfied on 1 node) do-not-log-me"
        client = tasks_answering("pending", planted)
        result = described_class.new(client: client, engine: engine, logger: logger).execute(command("list_tasks"))

        expect(result.safe_metadata.to_s).not_to include("do-not-log-me")
      end
    end
  end

  # M01-18 §4 — the Service Spec the reconciler needs. Four typed keys, no
  # free-form passthrough: what is absent from the allowlist cannot be sent.
  describe "the Service Spec fields M01-18 adds" do
    def created_body(**payload)
      client = ScriptedClient.new("GET /services?" => response(200, []),
        "POST /services/create" => response(201, "ID" => "s1"), "GET /services/s1" => response(200, SERVICE))
      described_class.new(client: client, engine: engine, logger: logger)
        .execute(command("create_service", image: "img", **payload))
      client.calls.find { |m, _, _| m == "POST" }.last
    end

    it "translates resources into NanoCPUs and MemoryBytes under Limits and Reservations" do
      body = created_body(resources: { "cpu_limit_nano" => 2_000_000_00, "memory_limit_bytes" => 536_870_912,
        "cpu_reservation_nano" => 100_000_000, "memory_reservation_bytes" => 268_435_456 })

      expect(body.dig("TaskTemplate", "Resources", "Limits"))
        .to eq("NanoCPUs" => 2_000_000_00, "MemoryBytes" => 536_870_912)
      expect(body.dig("TaskTemplate", "Resources", "Reservations"))
        .to eq("NanoCPUs" => 100_000_000, "MemoryBytes" => 268_435_456)
    end

    it "translates placement constraints" do
      body = created_body(placement: [ "node.role==worker" ])

      expect(body.dig("TaskTemplate", "Placement", "Constraints")).to eq([ "node.role==worker" ])
    end

    it "translates a healthcheck" do
      body = created_body(healthcheck: { "Test" => [ "CMD", "true" ], "Interval" => 10_000_000_000 })

      expect(body.dig("TaskTemplate", "ContainerSpec", "HealthCheck", "Test")).to eq([ "CMD", "true" ])
    end

    it "carries the update policy the caller sends and never a rollback action of its own" do
      body = created_body(update_config: { "Parallelism" => 1, "FailureAction" => "pause" })

      expect(body["UpdateConfig"]).to eq("Parallelism" => 1, "FailureAction" => "pause")
    end

    it "never publishes a port, mounts a volume or grants a privilege (AC12)" do
      body = created_body

      expect(body).not_to have_key("EndpointSpec")
      expect(body.dig("TaskTemplate", "ContainerSpec")).not_to have_key("Mounts")
      expect(body.dig("TaskTemplate", "ContainerSpec")).not_to have_key("Privileged")
      expect(JSON.generate(body)).not_to include("docker.sock")
    end

    it "refuses a published port, a mount and a privilege before touching the Engine" do
      client = ScriptedClient.new
      ex = described_class.new(client: client, engine: engine, logger: logger)

      %i[ports mounts privileged].each do |key|
        expect { ex.execute(command("create_service", image: "img", key => true)) }
          .to raise_error(ExecutorCommand::Invalid, /#{key}/)
      end
      expect(client.calls).to be_empty
    end
  end

  # AC12 — planted values, and the log is the sink.
  describe "the log (AC12)" do
    it "records operation, resource, correlation, duration, outcome and observed version" do
      captured = []
      allow(logger).to receive(:info) { |entry| captured << entry }
      executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200, SERVICE)).execute(command("inspect_service"))

      entry = captured.last
      expect(entry).to include(event: "executor.inspect_service", command_id: "cmd_inspect_service",
        correlation_id: "corr_1", resource_id: "svc_1", outcome: "APPLIED", observed_runtime_version: 12)
      expect(entry[:duration_ms]).to be_a(Integer)
    end

    it "never logs a join token, a registry credential or a bearer token from a transport error" do
      captured = []
      allow(logger).to receive(:info) { |entry| captured << entry }
      planted = "curl: (52) X-Registry-Auth: not-a-real-registry-auth-value-x1 " \
                "Authorization: Bearer not-a-real-bearer-token-x1 SWMTKN-1-example-not-a-real-token-x1"
      ex = executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => EngineClient::Error.new(:transient, planted))

      ex.execute(command("inspect_service"))

      text = captured.map(&:to_s).join
      expect(text).not_to include("not-a-real-registry-auth-value-x1")
      expect(text).not_to include("not-a-real-bearer-token-x1")
      expect(text).not_to include("SWMTKN")
      expect(text).to include("[REDACTED]")
    end

    it "never logs a response body" do
      captured = []
      allow(logger).to receive(:info) { |entry| captured << entry }
      executor("GET /services?" => response(200, [ SERVICE ]),
        "GET /services/s1" => response(200,
SERVICE.merge("Secret" => "do-not-log-me"))).execute(command("inspect_service"))

      expect(captured.map(&:to_s).join).not_to include("do-not-log-me")
    end
  end
end
