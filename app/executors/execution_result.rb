# What the Swarm Executor answers with — doc 07 §20.2, field for field.
#
# ## Five outcomes, and a sixth situation that is not one
#
# `outcome` is the enum the approved contract declares, and it is not widened
# here. doc 07 §5.3 names a sixth *situation* — "Docker aplicou, mas resposta foi
# perdida" — whose rule is *"nunca repetir cegamente: observar actual state
# primeiro"*. It is carried as `RETRYABLE` plus `error_code: UNKNOWN_OUTCOME` and
# `observe_before_retry: true`, so a caller that only reads the enum still does
# the safe thing (retries through the reconciler, which observes first), and a
# caller that reads the flag knows it must not resend. A result marked this way
# is never `FAILED`: nothing is known to have failed.
#
# ## `safe_metadata` is named for what it is
#
# Whatever goes in it reaches logs and the audit trail. The executor puts
# identifiers, versions and counts there — never a spec, never a body, never an
# error message verbatim.
class ExecutionResult < Data.define(:command_id, :outcome, :observed_runtime_version,
  :runtime_resource_ids, :safe_metadata, :error_code, :observe_before_retry, :observed)
  APPLIED = "APPLIED"
  NOOP = "NOOP"
  CONFLICT = "CONFLICT"
  RETRYABLE = "RETRYABLE"
  FAILED = "FAILED"
  OUTCOMES = [ APPLIED, NOOP, CONFLICT, RETRYABLE, FAILED ].freeze

  # doc 09 §28's stable vocabulary, plus the executor's own transport codes.
  UNKNOWN_OUTCOME = "UNKNOWN_OUTCOME"
  ENGINE_UNAVAILABLE = "ENGINE_UNAVAILABLE"
  ENGINE_TIMEOUT = "ENGINE_TIMEOUT"
  NOT_A_MANAGER = "NOT_A_MANAGER"
  RUNTIME_REJECTED = "RUNTIME_REJECTED"

  def initialize(command_id:, outcome:, observed_runtime_version: nil, runtime_resource_ids: [],
    safe_metadata: {}, error_code: nil, observe_before_retry: false, observed: nil)
    raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

    super(command_id: command_id, outcome: outcome,
      observed_runtime_version: observed_runtime_version,
      runtime_resource_ids: Array(runtime_resource_ids).freeze,
      safe_metadata: safe_metadata.to_h.freeze, error_code: error_code,
      observe_before_retry: observe_before_retry, observed: observed)
  end

  def applied? = outcome == APPLIED
  def noop? = outcome == NOOP
  def conflict? = outcome == CONFLICT
  def retryable? = outcome == RETRYABLE
  def failed? = outcome == FAILED

  # Converged: the runtime is in the desired state, whether this call put it
  # there or found it there.
  def converged? = applied? || noop?

  # The sixth situation. Never `failed?`, and never to be resent without an
  # observation in between.
  def unknown_outcome? = error_code == UNKNOWN_OUTCOME

  class << self
    def applied(command, version: nil, ids: [], observed: nil, **metadata)
      new(command_id: command.id, outcome: APPLIED, observed_runtime_version: version,
        runtime_resource_ids: ids, safe_metadata: metadata, observed: observed)
    end

    def noop(command, version: nil, ids: [], observed: nil, **metadata)
      new(command_id: command.id, outcome: NOOP, observed_runtime_version: version,
        runtime_resource_ids: ids, safe_metadata: metadata, observed: observed)
    end

    def conflict(command, version: nil, ids: [], **metadata)
      new(command_id: command.id, outcome: CONFLICT, observed_runtime_version: version,
        runtime_resource_ids: ids, safe_metadata: metadata, error_code: "CONFLICT")
    end

    def retryable(command, code, **metadata)
      new(command_id: command.id, outcome: RETRYABLE, safe_metadata: metadata, error_code: code)
    end

    def failed(command, code, **metadata)
      new(command_id: command.id, outcome: FAILED, safe_metadata: metadata, error_code: code)
    end

    # doc 07 §5.3, "Unknown outcome". RETRYABLE by enum, with the flag that turns
    # "retry" into "observe, then decide".
    def unknown(command, **metadata)
      new(command_id: command.id, outcome: RETRYABLE, safe_metadata: metadata,
        error_code: UNKNOWN_OUTCOME, observe_before_retry: true)
    end
  end
end
