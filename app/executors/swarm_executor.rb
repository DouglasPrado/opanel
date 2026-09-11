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
    "create_service" => %w[name image command args env replicas labels networks
                           resources placement healthcheck update_config].freeze,
    "update_service_spec" => %w[image command args env replicas labels version
                                resources placement healthcheck update_config].freeze,
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
    by_label = find_by_label("/services", command.resource_id)
    if by_label
      response = client.get("/services/#{by_label['ID']}")
      if response.ok?
        observation = normalize_service_observation(response.body)
        return ExecutionResult.applied(command, version: observation.version,
          ids: [ by_label["ID"] ], observed: observation)
      else
        return outcome_for(command, response)
      end
    end

    ExecutionResult.failed(command, "NOT_FOUND")
  end

  def do_create_service(command)
    existing = find_by_label("/services", command.resource_id)
    if existing
      observation = normalize_service_observation(existing)
      return ExecutionResult.noop(command, version: observation.version, ids: [ existing["ID"] ],
        adopted: true, observed: observation)
    end

    response = client.post("/services/create", service_spec(command))
    return outcome_for(command, response) unless response.ok?

    created = client.get("/services/#{identifier(response.body['ID'])}")
    observation = normalize_service_observation(created.body) if created.ok?
    ExecutionResult.applied(command, version: observation&.version, ids: [ response.body["ID"] ],
      observed: observation)
  end

  def do_update_service_spec(command)
    # ADR-0009 §5: find by label first to get the runtime ID
    by_label = find_by_label("/services", command.resource_id)
    unless by_label
      return ExecutionResult.failed(command, "NOT_FOUND")
    end

    id = by_label["ID"]
    current_response = client.get("/services/#{id}")
    return outcome_for(command, current_response) unless current_response.ok?

    current = current_response.body

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

    spec = merge_spec(current["Spec"], command)

    response = client.post("/services/#{id}/update?version=#{version.to_i}", spec)
    return outcome_for(command, response) unless response.ok?

    updated = client.get("/services/#{id}")
    ExecutionResult.applied(command, version: version_of(updated.body), ids: [ current["ID"] ])
  end

  def do_remove_service(command)
    # ADR-0009 §5: find by ownership label first, like create/inspect
    by_label = find_by_label("/services", command.resource_id)
    if by_label
      response = client.delete("/services/#{by_label['ID']}")
      return ExecutionResult.noop(command, absent: true) if response.not_found?
      return outcome_for(command, response) unless response.ok?
      return ExecutionResult.applied(command, ids: [ by_label["ID"] ])
    end

    ExecutionResult.noop(command, absent: true)
  end

  def do_create_network(command)
    existing = find_by_label("/networks", command.resource_id)
    if existing
      observation = normalize_network_observation(existing)
      return ExecutionResult.noop(command, version: observation.version, ids: [ existing["Id"] ],
        adopted: true, observed: observation)
    end

    # Before creating, check for name conflicts with unowned networks (AC6, BLOCKED).
    desired_name = command.payload.fetch("name", command.resource_id)
    conflict_check = check_network_name_conflict(command, desired_name)
    if conflict_check
      return conflict_check
    end

    response = client.post("/networks/create", network_spec(command))
    return outcome_for(command, response) unless response.ok?

    # Read back the created network to get a full observation
    network_id = response.body["ID"] || response.body["Id"]
    created = client.get("/networks/#{network_id}") if network_id
    if created && created.ok?
      observation = normalize_network_observation(created.body)
      return ExecutionResult.applied(command, version: observation.version, ids: [ network_id ],
        observed: observation)
    end

    # If we couldn't read the network back, still return success with the ID from create
    ExecutionResult.applied(command, ids: [ network_id ])
  end

  def do_inspect_network(command)
    # Find by ownership label (ADR-0009 §5: owned networks addressed by label).
    by_label = find_by_label("/networks", command.resource_id)
    if by_label
      response = client.get("/networks/#{by_label['Id']}")
      if response.ok?
        observation = normalize_network_observation(response.body)
        return ExecutionResult.applied(command, version: observation.version,
          ids: [ by_label["Id"] ], observed: observation)
      end
    end

    # Not found by label = not found (name conflicts are checked in do_create_network).
    ExecutionResult.failed(command, "NOT_FOUND")
  end

  def do_remove_network(command)
    by_label = find_by_label("/networks", command.resource_id)
    if by_label
      response = client.delete("/networks/#{by_label['Id']}")
      return ExecutionResult.noop(command, absent: true) if response.not_found?
      return outcome_for(command, response) unless response.ok?
      return ExecutionResult.applied(command, ids: [ by_label["Id"] ])
    end

    ExecutionResult.noop(command, absent: true)
  end

  def do_list_nodes(command)
    response = client.get("/nodes")
    return outcome_for(command, response) unless response.ok?

    nodes = Array(response.body)
    ExecutionResult.applied(command, ids: nodes.map { |n| n["ID"] }, count: nodes.length,
      managers: nodes.count { |n| n.dig("Spec", "Role") == "manager" })
  end

  def do_inspect_node(command)
    # Nodes are not created by the platform; addressed directly by Swarm node ID (ADR-0009 §5).
    response = client.get("/nodes/#{identifier(command.resource_id)}")
    return outcome_for(command, response) unless response.ok?

    observation = normalize_node_observation(response.body)
    ExecutionResult.applied(command, version: observation.version, ids: [ response.body["ID"] ],
      observed: observation)
  end

  # Bounded, and demultiplexed: the Engine frames non-TTY logs as 8-byte headers
  # (stream, three zero bytes, big-endian length) followed by the payload.
  def do_service_logs(command)
    tail = command.payload.fetch("tail", 100).to_i.clamp(1, MAX_LOG_TAIL)
    # ADR-0009 §5: find by ownership label first
    by_label = find_by_label("/services", command.resource_id)
    return ExecutionResult.failed(command, "NOT_FOUND") unless by_label

    response = client.get("/services/#{by_label['ID']}/logs?stdout=true&stderr=true&tail=#{tail}")
    return outcome_for(command, response) unless response.ok?

    lines = demultiplex(response.raw)
    ExecutionResult.applied(command, ids: [ by_label["ID"] ], lines: lines, line_count: lines.length)
  end

  def do_list_tasks(command)
    # ADR-0009 §5: find by ownership label first to get the runtime service ID
    by_label = find_by_label("/services", command.resource_id)
    return ExecutionResult.failed(command, "NOT_FOUND") unless by_label

    filter = JSON.generate("service" => [ by_label["ID"] ])
    response = client.get("/tasks?filters=#{CGI.escape(filter)}")
    return outcome_for(command, response) unless response.ok?

    tasks = Array(response.body)
    current = current_tasks(tasks, by_label)
    metadata = { count: tasks.length, current_count: current.length,
                 states: tasks.map { |t| t.dig("Status", "State") }.tally }
    code = blocking_code(current)
    metadata[:blocking_code] = code if code

    ExecutionResult.applied(command, ids: tasks.map { |t| t["ID"] }, **metadata)
  end

  # `/tasks` answers with **history**, not with the present. Swarm retains
  # terminated tasks (`task-history-limit`, default 5), so a task that failed
  # under a spec the operator has already replaced stays in the response
  # indefinitely. Classifying from that set means a Service whose bad digest was
  # repaired is reported blocked on the very pass that converged it, and can
  # never leave that state until history rolls over (review F-1).
  #
  # A task describes the service's *current* desired state when it is the
  # highest revision of its slot. Each slot can have multiple revisions (when a
  # task fails and is replaced); only the highest revision represents current
  # work, and terminated tasks are kept in history only up to `task-history-limit`
  # (default 5). We classify only from current tasks, filtering by slot revision
  # to exclude historical attempts that the Engine already replaced.
  SUPERSEDED_DESIRED_STATES = %w[shutdown remove orphaned].freeze

  def current_tasks(tasks, service)
    # A task is current if within its slot it has the highest Version.Index
    # (meaning it's not a historical attempt that Swarm kept in task-history),
    # and if its desired state is not shutdown/remove/orphaned and its image
    # spec matches the service's desired image.
    #
    # When a service is updated to a new image, Swarm creates new tasks with
    # higher Version.Index in the same slot. Old tasks are kept in history but
    # have lower indices. Filtering by Slot+HighestVersion removes them, so a
    # Service whose image was fixed is not reported blocked by the old task.
    by_slot = {}
    tasks.each do |task|
      slot = task["Slot"]
      next if slot.nil?

      version_index = task.dig("Version", "Index").to_i
      current = by_slot[slot]

      if current.nil? || version_index > current.dig("Version", "Index").to_i
        by_slot[slot] = task
      end
    end

    # Use the filtered tasks if we found any with Slot; otherwise fall back
    # to all tasks. (Slot should always be present for service tasks.)
    current = by_slot.empty? ? tasks : by_slot.values
    desired_image = service.dig("Spec", "TaskTemplate", "ContainerSpec", "Image")

    current.reject do |task|
      SUPERSEDED_DESIRED_STATES.include?(task["DesiredState"].to_s.downcase) ||
        superseded_spec?(task, desired_image)
    end
  end

  def superseded_spec?(task, desired_image)
    image = task.dig("Spec", "ContainerSpec", "Image")
    return false if image.nil? || desired_image.nil?

    image != desired_image
  end

  # M01-18 AC9. The daemon accepts a service it cannot schedule and a digest it
  # cannot resolve — both answer 201 — so the only observable cause is the task.
  # What crosses the boundary is a **classification**, never the daemon's text:
  # `safe_metadata` reaches the forensic log line, and `ExecutionResult` says in
  # its own words that it carries no message verbatim.
  TASK_BLOCKERS = {
    "PLACEMENT_IMPOSSIBLE" => /no suitable node|scheduling constraints/i,
    "IMAGE_UNAVAILABLE" => /failed to resolve reference|no such image|manifest unknown|not found/i
  }.freeze

  def blocking_code(tasks)
    tasks.each do |task|
      error = task.dig("Status", "Err").to_s
      next if error.empty?

      match = TASK_BLOCKERS.find { |_code, pattern| error.match?(pattern) }
      return match.first if match
    end

    nil
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

  # ---- normalizers: Engine JSON → RuntimeObservation (ADR-0009 §3) ----------

  # Normalize a network Engine response into a RuntimeObservation.
  def normalize_network_observation(body)
    Opanel::RuntimeObservation.new(
      kind: "network",
      runtime_id: body["Id"],
      name: body["Name"],
      labels: body["Labels"] || {},
      version: version_of(body),
      attributes: {
        "driver" => body["Driver"],
        "scope" => body["Scope"],
        "attachable" => body["Attachable"],
        "internal" => body["Internal"]
      }.compact
    )
  end

  # Normalize a service Engine response into a RuntimeObservation.
  def normalize_service_observation(body)
    Opanel::RuntimeObservation.new(
      kind: "service",
      runtime_id: body["ID"],
      name: body["Spec"]["Name"],
      labels: body["Spec"]["Labels"] || {},
      version: version_of(body),
      attributes: {
        "image" => body.dig("Spec", "TaskTemplate", "ContainerSpec", "Image"),
        "replicas" => body.dig("Spec", "Mode", "Replicated", "Replicas"),
        "mode" => body["Spec"]["Mode"].is_a?(Hash) ? body["Spec"]["Mode"].keys.first : "replicated"
      }.compact
    )
  end

  # Normalize a node Engine response into a RuntimeObservation.
  def normalize_node_observation(body)
    Opanel::RuntimeObservation.new(
      kind: "node",
      runtime_id: body["ID"],
      name: body["Description"]["Hostname"],
      labels: body["Description"]["Labels"] || {},
      version: version_of(body),
      attributes: {
        "role" => body.dig("Spec", "Role"),
        "availability" => body.dig("Spec", "Availability"),
        "state" => body.dig("Status", "State"),
        "hostname" => body.dig("Description", "Hostname"),
        "advertise_address" => body.dig("Description", "Engine", "EngineVersion")
      }.compact
    )
  end

  # Check if a network name conflicts with an unowned network.
  # Returns a FAILED result if conflict found, nil otherwise.
  def check_network_name_conflict(command, desired_name)
    response = client.get("/networks")
    return nil unless response.ok?

    Array(response.body).each do |net|
      if net["Name"] == desired_name
        observation = normalize_network_observation(net)
        unless Opanel::Ownership.managed_by_platform?(observation)
          # Unowned network with same name → BLOCKED
          return ExecutionResult.failed(command, "RESOURCE_NAME_CONFLICT", conflict_name: desired_name)
        end
      end
    end

    nil
  end

  # ---- helpers -------------------------------------------------------------

  def identifier(value)
    text = value.to_s
    raise ExecutorCommand::Invalid, "#{text.inspect} is not a runtime identifier" unless text.match?(ExecutorCommand::RUNTIME_IDENTIFIER)

    text
  end

  # Find a resource by its ownership labels (ADR-0009 §5).
  # The resource_id is always in external format (svc_01…, env_01…). We search
  # for it in the appropriate ownership label (service_id or environment_id).
  # This is part of idempotent create: if the resource exists with our labels,
  # adopt it rather than failing (doc 07 §6.2, AC7).
  def find_by_label(collection, resource_id)
    # Determine which label key to search based on collection type.
    # Services are identified by com.opanel.service_id, Networks by environment_id.
    label_key = collection == "/services" ? "service_id" : "environment_id"
    label_name = "#{Opanel::Ownership::NAMESPACE}.#{label_key}"

    # resource_id is already in external format; validate and use it directly.
    validated_id = identifier(resource_id)

    filter = JSON.generate("label" => [ "#{label_name}=#{validated_id}" ])
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
          "Command" => p["command"], "Args" => p["args"], "Env" => p["env"],
          "HealthCheck" => p["healthcheck"]
        }.compact,
        "Networks" => Array(p["networks"]).map { |n| { "Target" => n } },
        "Resources" => resources_spec(p["resources"]),
        "Placement" => placement_spec(p["placement"])
      }.compact,
      "Mode" => { "Replicated" => { "Replicas" => p.fetch("replicas", 1).to_i } },
      "UpdateConfig" => p["update_config"]
    }.compact
  end

  # M01-18 §4. The caller sends Engine units — nanocpus and bytes — because the
  # conversion from the product's units is a domain decision, and a boundary
  # that silently rescales a number is a boundary that can be wrong by 1000.
  def resources_spec(resources)
    return nil if resources.blank?

    limits = {
      "NanoCPUs" => resources["cpu_limit_nano"], "MemoryBytes" => resources["memory_limit_bytes"]
    }.compact
    reservations = {
      "NanoCPUs" => resources["cpu_reservation_nano"],
      "MemoryBytes" => resources["memory_reservation_bytes"]
    }.compact

    spec = { "Limits" => limits.presence, "Reservations" => reservations.presence }.compact
    spec.presence
  end

  def placement_spec(constraints)
    return nil if Array(constraints).empty?

    { "Constraints" => Array(constraints) }
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
    container["HealthCheck"] = p["healthcheck"] if p.key?("healthcheck")
    spec["Labels"] = (spec["Labels"] || {}).merge(p["labels"]) if p.key?("labels")
    spec["Mode"] = { "Replicated" => { "Replicas" => p["replicas"].to_i } } if p.key?("replicas")
    spec["TaskTemplate"]["Resources"] = resources_spec(p["resources"]) if p.key?("resources")
    spec["TaskTemplate"]["Placement"] = placement_spec(p["placement"]) if p.key?("placement")
    spec["UpdateConfig"] = p["update_config"] if p.key?("update_config")
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
