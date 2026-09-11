# A scripted stand-in for the Swarm Executor, for the parts of M01-18 that are
# about PostgreSQL rather than about Docker.
#
# What a real daemon must answer — that a Service is really created, that a
# stale version is really refused, that a restarted reconciler really does not
# duplicate anything — is proved in `spec/integration/service_*_lab_spec.rb`
# against the lab Engine. What is scripted here is the *sequence*: which command
# the reconciler sends next, and what it writes when the answer is each of the
# outcomes a daemon cannot be asked to produce on demand.
#
# Every call is recorded, so an example can assert that an inspect precedes a
# repeat (AC5) rather than trusting that it did.
class FakeSwarmExecutor
  attr_reader :calls

  # @param script [Hash{String => Object}] operation type => ExecutionResult, an
  #   Array of results consumed in order, or a callable taking the command.
  def initialize(script = {})
    @script = script
    @calls = []
  end

  def execute(command)
    @calls << command
    answer(command)
  end

  # The executor's own contract: observe first, and only then decide whether the
  # effect still has to be applied (ADR-0009, doc 07 §5.3).
  def retry_after_observing(command)
    observation = execute(observe_command(command))
    return ExecutionResult.noop(command, reobserved: true, observed: observation.observed) if observation.converged?

    execute(command)
  end

  def types = @calls.map(&:type)

  private

  def observe_command(command)
    ExecutorCommand.new(id: "#{command.id}:observe", type: "inspect_service",
      cluster_id: command.cluster_id, resource_type: command.resource_type,
      resource_id: command.resource_id, correlation_id: command.correlation_id)
  end

  def answer(command)
    value = @script.fetch(command.type) { raise "unscripted executor call: #{command.type}" }
    value = value.shift if value.is_a?(Array)
    value = value.call(command) if value.respond_to?(:call)
    value
  end
end

module SwarmObservations
  module_function

  # The shape ADR-0009 §2 fixes for a service: flattened labels, and an
  # attribute allowlist of image, replicas and mode.
  def service_observation(service, image: nil, replicas: nil, runtime_id: "runtime1", revision: nil, labels: nil,
version: nil)
    Opanel::RuntimeObservation.new(
      kind: "service",
      runtime_id: runtime_id,
      name: service.technical_name,
      labels: labels || Opanel::Ownership.labels_for(service).merge(
        "com.opanel.desired_revision" => (revision || service.desired_revision).to_s
      ),
      version: version || 12,
      attributes: {
        "image" => image || ServiceReconciler::SpecTranslation.image_for(service),
        "replicas" => replicas || service.replicas,
        "mode" => "Replicated"
      }
    )
  end

  def applied(observation, ids: [ "runtime1" ])
    ExecutionResult.new(command_id: "cmd", outcome: ExecutionResult::APPLIED,
      observed_runtime_version: observation&.version, runtime_resource_ids: ids,
      safe_metadata: {}, observed: observation)
  end

  def not_found
    ExecutionResult.new(command_id: "cmd", outcome: ExecutionResult::FAILED, error_code: "NOT_FOUND",
      safe_metadata: {})
  end

  def tasks(blocking_code: nil, count: 1)
    metadata = { count: count, states: { "running" => count } }
    metadata[:blocking_code] = blocking_code if blocking_code

    ExecutionResult.new(command_id: "cmd", outcome: ExecutionResult::APPLIED, safe_metadata: metadata)
  end

  def unknown_outcome
    ExecutionResult.new(command_id: "cmd", outcome: ExecutionResult::RETRYABLE,
      error_code: ExecutionResult::UNKNOWN_OUTCOME, observe_before_retry: true, safe_metadata: {})
  end

  def conflict
    ExecutionResult.new(command_id: "cmd", outcome: ExecutionResult::CONFLICT, error_code: "CONFLICT",
      safe_metadata: {})
  end
end

RSpec.configure { |config| config.include SwarmObservations }
