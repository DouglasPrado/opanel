require "cgi"
require "json"
require "stringio"

# The privileged Swarm Executor — doc 07 §2.2, §20, §21; Annex C §8.
#
# ## This file is the allowlist
#
# `OPERATIONS` is the complete set of things the platform can do to the Docker
# Engine, and each one is a method with typed arguments that builds an Engine API
# path from a validated identifier. There is no `exec`, no `run`, no method that
# takes a command line, and no way to pass a free argument through to the daemon
# (doc 07 §21, the boxed prohibition). Reading this file is reading the whole
# privilege, which is the point of having exactly one.
#
# ## It decides nothing about the product
#
# Authorization happened in the Application Layer before an `ExecutorCommand`
# was built (Annex I §4.1). The executor validates the command's shape, refuses
# to run anywhere but on a Manager, applies, and reports. Whether the actor was
# allowed is not its question.
#
# ## Idempotent by construction (the Story's "Async / Control Plane")
#
# - `create_*` looks for a resource already carrying this Command's
#   `opanel.resource` label before creating one, and answers `NOOP` with what it
#   found — adoption, not error (AC7).
# - `update_service_spec` sends the version it observed; a revision that moved
#   underneath it comes back `CONFLICT` for the reconciler to re-observe (AC5).
# - `remove_*` of something already gone is `NOOP`: the desired state is
#   "absent", and it is (AC8).
# - A lost answer to a mutation is reported as unknown, never as failure, and
#   `retry_after_observing` is the only sanctioned way to try again (AC6).
class SwarmExecutor
  # The whole allowlist: operation name → payload keys it accepts. A key outside
  # the list is refused before the daemon is reached (`ExecutorCommand#validate!`).
  OPERATIONS = {
    "inspect_service" => %w[].freeze,
    "create_service" => %w[name image command args env replicas labels networks].freeze,
    "update_service_spec" => %w[image command args env replicas labels version].freeze,
    "remove_service" => %w[].freeze,
    "create_network" => %w[name labels attachable].freeze,
    "inspect_network" => %w[].freeze,
    "remove_network" => %w[].freeze,
    "list_nodes" => %w[].freeze,
    "inspect_node" => %w[].freeze,
    "service_logs" => %w[tail].freeze,
    "list_tasks" => %w[].freeze
  }.freeze

  # doc 07 §5.3 → doc 09 §28.
  CONFLICT_MESSAGE = /update out of sequence|already exists|name conflicts/i
  MAX_LOG_TAIL = 1000

  def initialize(client: EngineClient.new, engine: SwarmBootstrap, logger: Rails.logger)
    @client = client
    @engine = engine
    @logger = logger
  end

  # The single entry point. Everything below is reached only through it.
  def execute(command)
    started = monotonic_now
    # `send`, not `public_send`: the operations are private on purpose (nothing
    # outside reaches one without going through `guarded`), and the name is taken
    # from `OPERATIONS` — checked there before this line runs — never from input.
    result = guarded(command) { send(:"do_#{command.type}", command) }
    record(command, result, started)
    result
  end

  # AC6. After an unknown outcome the reconciler does not resend: it asks the
  # executor to observe first. If the runtime already shows the effect the
  # answer is `NOOP`; if it does not, the command is applied once more — and that
  # is the only path on which a mutation is ever re-issued.
  def retry_after_observing(command)
    observation = observe(command)

    # A daemon that will not answer, or an observation that failed for a reason
    # other than absence, is returned as-is: nothing can be decided from it.
    # Absence is different — it is *the* converged state of a remove and the
    # "apply again" state of a create — so NOT_FOUND flows into the decision
    # below rather than short-circuiting it. The first version returned early
    # on any failure and the unit spec caught it: a remove of an absent service
    # came back FAILED instead of NOOP.
    return observation if observation.retryable?
    return observation if observation.failed? && observation.error_code != "NOT_FOUND"

    if converged_by_observation?(command, observation)
      return ExecutionResult.noop(command, version: observation.observed_runtime_version,
        ids: observation.runtime_resource_ids, reobserved: true)
    end

    execute(command)
  end

  private

  attr_reader :client, :engine, :logger

  # ---- the operations ------------------------------------------------------

  def do_inspect_service(command)
    response = client.get("/services/#{identifier(command.resource_id)}")
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, version: version_of(response.body), ids: [ response.body["ID"] ],
      name: response.body.dig("Spec", "Name"))
  end

  def do_create_service(command)
    existing = find_by_label("/services", command.resource_id)
    return ExecutionResult.noop(command, version: version_of(existing), ids: [ existing["ID"] ],
      adopted: true) if existing

    response = client.post("/services/create", service_spec(command))
    return outcome_for(command, response) unless response.ok?

    created = client.get("/services/#{identifier(response.body['ID'])}")
    ExecutionResult.applied(command, version: version_of(created.body), ids: [ response.body["ID"] ])
  end

  def do_update_service_spec(command)
    id = identifier(command.resource_id)
    current = client.get("/services/#{id}")
    return outcome_for(command, current) unless current.ok?

    # The version the caller **observed when it computed its diff** — never one
    # read here. The first version of this method fell back to the index it had
    # just read, which is the read-modify-write-blind sequence the transport
    # choice exists to avoid: a reconciler that diffed against an older revision
    # and then called this would overwrite whatever moved in between with no
    # CONFLICT at all (review H-1). Without a baseline there is no CAS, so a
    # command that carries none is refused before the daemon is asked.
    version = command.payload["version"]
    if version.nil?
      raise ExecutorCommand::Invalid,
        "update_service_spec needs the version the caller observed (payload[\"version\"]); " \
        "an update with no baseline is a blind overwrite"
    end

    spec = merge_spec(current.body["Spec"], command)

    response = client.post("/services/#{id}/update?version=#{version.to_i}", spec)
    return outcome_for(command, response) unless response.ok?

    updated = client.get("/services/#{id}")
    ExecutionResult.applied(command, version: version_of(updated.body), ids: [ current.body["ID"] ])
  end

  def do_remove_service(command)
    response = client.delete("/services/#{identifier(command.resource_id)}")
    return ExecutionResult.noop(command, absent: true) if response.not_found?
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, ids: [ command.resource_id ])
  end

  def do_create_network(command)
    existing = find_by_label("/networks", command.resource_id)
    return ExecutionResult.noop(command, ids: [ existing["Id"] ], adopted: true) if existing

    response = client.post("/networks/create", network_spec(command))
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, ids: [ response.body["Id"] ])
  end

  def do_inspect_network(command)
    response = client.get("/networks/#{identifier(command.resource_id)}")
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, ids: [ response.body["Id"] ], name: response.body["Name"],
      driver: response.body["Driver"])
  end

  def do_remove_network(command)
    response = client.delete("/networks/#{identifier(command.resource_id)}")
    return ExecutionResult.noop(command, absent: true) if response.not_found?
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, ids: [ command.resource_id ])
  end

  def do_list_nodes(command)
    response = client.get("/nodes")
    return outcome_for(command, response) unless response.ok?

    nodes = Array(response.body)
    ExecutionResult.applied(command, ids: nodes.map { |n| n["ID"] }, count: nodes.length,
      managers: nodes.count { |n| n.dig("Spec", "Role") == "manager" })
  end

  def do_inspect_node(command)
    response = client.get("/nodes/#{identifier(command.resource_id)}")
    return outcome_for(command, response) unless response.ok?

    ExecutionResult.applied(command, version: version_of(response.body), ids: [ response.body["ID"] ],
      role: response.body.dig("Spec", "Role"), availability: response.body.dig("Spec", "Availability"),
      state: response.body.dig("Status", "State"))
  end

  # Bounded, and demultiplexed: the Engine frames non-TTY logs as 8-byte headers
  # (stream, three zero bytes, big-endian length) followed by the payload.
  def do_service_logs(command)
    tail = command.payload.fetch("tail", 100).to_i.clamp(1, MAX_LOG_TAIL)
    response = client.get("/services/#{identifier(command.resource_id)}/logs?stdout=true&stderr=true&tail=#{tail}")
    return outcome_for(command, response) unless response.ok?

    lines = demultiplex(response.raw)
    ExecutionResult.applied(command, ids: [ command.resource_id ], lines: lines, line_count: lines.length)
  end

  def do_list_tasks(command)
    filter = JSON.generate("service" => [ identifier(command.resource_id) ])
    response = client.get("/tasks?filters=#{CGI.escape(filter)}")
    return outcome_for(command, response) unless response.ok?

    tasks = Array(response.body)
    ExecutionResult.applied(command, ids: tasks.map { |t| t["ID"] }, count: tasks.length,
      states: tasks.map { |t| t.dig("Status", "State") }.tally)
  end

  # ---- the guard rails -----------------------------------------------------

  # Shape first (no daemon round trip for a malformed command), then the Manager
  # check (read from the daemon every time: a demoted node is refused on the next
  # call, with nothing to invalidate), then the operation — with every transport
  # failure turned into the result the reconciler needs rather than an exception
  # it would have to classify itself.
  def guarded(command)
    keys = OPERATIONS.fetch(command.type) do
      raise ExecutorCommand::Invalid, "#{command.type.inspect} is not an executor operation"
    end
    command.validate!(keys)

    refusal = manager_refusal(command)
    return refusal if refusal

    yield
  rescue EngineClient::Error => error
    error.unknown_outcome? ? ExecutionResult.unknown(command, transport: error.message) :
      ExecutionResult.retryable(command, ExecutionResult::ENGINE_UNAVAILABLE, transport: error.message)
  end

  # AC9. Closed: a worker answers FAILED with its own code, and nothing runs.
  def manager_refusal(command)
    info = engine.info
    return nil if info.manager?

    ExecutionResult.failed(command, ExecutionResult::NOT_A_MANAGER, node: info.node_id,
      swarm_state: info.swarm_state)
  rescue SwarmBootstrap::EngineError => error
    ExecutionResult.retryable(command, ExecutionResult::ENGINE_UNAVAILABLE, cause: error.cause_code)
  end

  # HTTP status → the result the reconciler acts on (doc 07 §5.3).
  def outcome_for(command, response)
    if response.conflict? || (response.server_error? && response.message.match?(CONFLICT_MESSAGE))
      ExecutionResult.conflict(command, http_status: response.status)
    elsif response.validation?
      ExecutionResult.failed(command, "VALIDATION_ERROR", http_status: response.status)
    elsif response.not_found?
      ExecutionResult.failed(command, "NOT_FOUND", http_status: response.status)
    elsif response.unavailable?
      ExecutionResult.retryable(command, ExecutionResult::ENGINE_UNAVAILABLE, http_status: response.status)
    else
      ExecutionResult.failed(command, ExecutionResult::RUNTIME_REJECTED, http_status: response.status)
    end
  end

  # ---- helpers -------------------------------------------------------------

  def identifier(value)
    text = value.to_s
    raise ExecutorCommand::Invalid, "#{text.inspect} is not a runtime identifier" unless text.match?(ExecutorCommand::RUNTIME_IDENTIFIER)

    text
  end

  # Find a resource by its ownership labels. The caller passes a resource_id
  # (in ULID or external format), and we look for it in the appropriate ownership label
  # (service_id or environment_id). The label stores the external format (e.g.,
  # "svc_01M..."), so we must normalize the resource_id to external format to search.
  # This is part of idempotent create: if the resource exists with our labels,
  # adopt it rather than failing (doc 07 §6.2, AC7).
  def find_by_label(collection, resource_id)
    # Determine which label key to search based on collection type.
    # Services are identified by com.opanel.service_id, Networks by environment_id.
    label_key = collection == "/services" ? "service_id" : "environment_id"
    label_name = "#{Opanel::Ownership::NAMESPACE}.#{label_key}"

    # Normalize resource_id to external format. It may arrive as either a ULID
    # or already in external format (e.g., "svc_01M..."). If it contains an underscore,
    # it's probably already prefixed, so use it directly. Otherwise, try to detect
    # the type and convert it.
    validated_id = identifier(resource_id)

    # If the resource_id contains an underscore, it's likely already in external
    # format (prefix_ulid). Use it directly without conversion.
    if validated_id.include?("_")
      external_id = validated_id
    else
      # It's a ULID. Determine the type and convert based on collection type.
      type = collection == "/services" ? :service : :environment
      external_id = Opanel::Identifier.external(type, validated_id)
    end

    filter = JSON.generate("label" => [ "#{label_name}=#{external_id}" ])
    response = client.get("#{collection}?filters=#{CGI.escape(filter)}")
    return nil unless response.ok?

    Array(response.body).first
  end

  def version_of(body) = body.is_a?(Hash) ? body.dig("Version", "Index") : nil

  def service_spec(command)
    p = command.payload
    {
      "Name" => p.fetch("name", command.resource_id),
      # Labels come from the application layer via the payload, computed using
      # Opanel::Ownership.labels_for(service). The executor is a consumer, not an author.
      "Labels" => p["labels"] || {},
      "TaskTemplate" => {
        "ContainerSpec" => {
          "Image" => p.fetch("image"),
          "Command" => p["command"], "Args" => p["args"], "Env" => p["env"]
        }.compact,
        "Networks" => Array(p["networks"]).map { |n| { "Target" => n } }
      },
      "Mode" => { "Replicated" => { "Replicas" => p.fetch("replicas", 1).to_i } }
    }
  end

  # The desired spec is the current one with the fields the command carries
  # replaced — a revision applied, not a blind imperative sequence.
  def merge_spec(current, command)
    p = command.payload
    spec = JSON.parse(JSON.generate(current))
    container = spec["TaskTemplate"]["ContainerSpec"]
    container["Image"] = p["image"] if p.key?("image")
    container["Command"] = p["command"] if p.key?("command")
    container["Args"] = p["args"] if p.key?("args")
    container["Env"] = p["env"] if p.key?("env")
    spec["Labels"] = (spec["Labels"] || {}).merge(p["labels"]) if p.key?("labels")
    spec["Mode"] = { "Replicated" => { "Replicas" => p["replicas"].to_i } } if p.key?("replicas")
    spec
  end

  def network_spec(command)
    p = command.payload
    {
      "Name" => p.fetch("name", command.resource_id),
      "Driver" => "overlay",
      "Attachable" => p.fetch("attachable", true),
      # Labels come from the application layer via the payload, computed using
      # Opanel::Ownership.labels_for(environment). The executor is a consumer, not an author.
      "Labels" => p["labels"] || {}
    }
  end

  def demultiplex(raw)
    lines = []
    io = StringIO.new(raw.to_s.b)
    while (header = io.read(8)) && header.bytesize == 8
      length = header.byteslice(4, 4).unpack1("N")
      chunk = io.read(length).to_s
      lines.concat(chunk.force_encoding("UTF-8").scrub.split("\n"))
    end
    lines
  end

  def observe(command)
    kind = command.type.split("_").last
    inspector = { "service" => "inspect_service", "network" => "inspect_network", "node" => "inspect_node" }[kind]
    return ExecutionResult.failed(command, "NOT_OBSERVABLE") if inspector.nil?

    execute(ExecutorCommand.new(id: "#{command.id}:observe", type: inspector, cluster_id: command.cluster_id,
      resource_type: command.resource_type, resource_id: command.resource_id,
      correlation_id: command.correlation_id))
  end

  # What "the runtime already shows the effect" means per operation. A remove is
  # converged when the inspect finds nothing; a create when it finds something;
  # an update when the observed version is past the one the command carried.
  def converged_by_observation?(command, observation)
    case command.type
    when "remove_service", "remove_network" then observation.failed? && observation.error_code == "NOT_FOUND"
    when "create_service", "create_network" then observation.applied?
    when "update_service_spec"
      observation.applied? && command.payload["version"] &&
        observation.observed_runtime_version.to_i > command.payload["version"].to_i
    else false
    end
  end

  # Every privileged call leaves a line (doc 07 §21, "correlação forense"):
  # operation, resource, correlation, duration, outcome, observed version — and
  # never a body. The message is redacted twice on purpose: the general patterns
  # and the join-token one, because a redaction one caller forgets is not one.
  def record(command, result, started)
    logger.info(
      event: "executor.#{command.type}",
      command_id: command.id,
      correlation_id: command.correlation_id,
      request_id: Current.request_id,
      resource_type: command.resource_type,
      resource_id: command.resource_id,
      cluster_id: command.cluster_id,
      duration_ms: ((monotonic_now - started) * 1000).round,
      outcome: result.outcome,
      error_code: result.error_code,
      observed_runtime_version: result.observed_runtime_version,
      runtime_resource_ids: result.runtime_resource_ids,
      transport: redact(result.safe_metadata[:transport] || result.safe_metadata["transport"])
    )
  end

  def redact(text)
    return nil if text.nil?

    SwarmBootstrap.redact(Opanel::Redaction.apply(text.to_s))
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
