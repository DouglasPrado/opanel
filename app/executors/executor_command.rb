# A command the Swarm Executor is asked to apply — doc 07 §20.1, field for field.
#
# ## The type is the allowlist
#
# `type` names one of the operations `SwarmExecutor::OPERATIONS` declares, and
# nothing else constructs. There is no field for a shell string, a raw argument
# list or an Engine path: what the executor can do to the daemon is the set of
# types, and reading that list is reading the whole privilege (doc 07 §21).
#
# ## The payload is validated before anything touches the socket
#
# Each type declares the keys it accepts. A key outside that set is refused, and
# so is any key `Opanel::Redaction` classifies as sensitive — a payload is a thing
# that gets logged, persisted on an Operation (`M01-13`) and reasoned about in a
# postmortem, and doc 07 §21 says it carries *"somente SecretVersion IDs"*, never
# plaintext (AC11). Refusing here, once, is what keeps every operation from having
# to remember.
class ExecutorCommand < Data.define(:id, :type, :cluster_id, :resource_type, :resource_id,
  :desired_revision, :requested_by, :correlation_id, :idempotency_key, :payload)
  class Invalid < StandardError; end

  # A Docker id or name: what may be interpolated into an Engine API path. Anything
  # else is refused before it reaches a URL — an id is not a place to put a query
  # string.
  RUNTIME_IDENTIFIER = /\A[A-Za-z0-9][A-Za-z0-9_.\-]{0,127}\z/

  def initialize(id:, type:, cluster_id:, resource_type:, resource_id:, desired_revision: nil,
    requested_by: nil, correlation_id: nil, idempotency_key: nil, payload: {})
    super(id: id.to_s, type: type.to_s, cluster_id: cluster_id, resource_type: resource_type.to_s,
      resource_id: resource_id.to_s, desired_revision: desired_revision,
      requested_by: requested_by, correlation_id: correlation_id,
      idempotency_key: idempotency_key, payload: deep_stringify(payload).freeze)
  end

  # Raises `Invalid` naming the first thing wrong. Called by the executor before
  # the manager check, so a malformed command never costs a daemon round trip.
  def validate!(allowed_keys)
    raise Invalid, "command #{id.inspect} has no type" if type.empty?
    raise Invalid, "command #{id.inspect} names no resource" if resource_id.empty?

    unknown = payload.keys - allowed_keys.map(&:to_s)
    unless unknown.empty?
      raise Invalid, "command #{id.inspect} (#{type}) carries keys outside its allowlist: " \
                     "#{unknown.sort.join(', ')}"
    end

    sensitive = sensitive_keys(payload)
    unless sensitive.empty?
      raise Invalid, "command #{id.inspect} (#{type}) carries secret material under " \
                     "#{sensitive.sort.join(', ')} — payloads carry SecretVersion ids only (doc 07 §21)"
    end

    self
  end

  private

  def deep_stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
    when Array then value.map { |v| deep_stringify(v) }
    else value
    end
  end

  # Every key at every depth. A secret two levels down is still a secret.
  def sensitive_keys(value, prefix = nil)
    return [] unless value.is_a?(Hash)

    value.flat_map do |key, nested|
      path = [ prefix, key ].compact.join(".")
      own = Opanel::Redaction.sensitive_key?(key) ? [ path ] : []
      own + sensitive_keys(nested, path)
    end
  end
end
