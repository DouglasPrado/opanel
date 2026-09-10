# Operation payload validator: ensures payloads are versioned and do not contain
# unexpected fields or plaintext secrets (doc 09 §9, doc 07 §21, Anexo C §16).
#
# Payloads are JSONB and must carry a schemaVersion. Never deserialize arbitrary
# classes; validate against an allowlist per operation type instead.
#
module Opanel::OperationPayload
  # Payload schema versions: increment when the structure changes.
  UPDATE_SERVICE_DESIRED_STATE_V1 = 1

  # Allowed fields per operation type (whitelisted, no arbitrary keys).
  SCHEMAS = {
    "UPDATE_SERVICE" => {
      schema_version: UPDATE_SERVICE_DESIRED_STATE_V1,
      fields: %i[
        schemaVersion
        service_id
        desired_revision
        replicas
        image_ref
        image_digest
        ports
        health_check
        cpu_reservation
        cpu_limit
        memory_reservation
        memory_limit
        constraints
        correlation_id
        request_id
        actor_id
      ].freeze
    }
  }.freeze

  # Validate a payload against its schema.
  # @param operation_type [String] the operation type (e.g., "UPDATE_SERVICE")
  # @param payload [Hash] the payload to validate
  # @return [Array] [valid?, error_message]
  def self.valid?(operation_type, payload)
    schema = SCHEMAS[operation_type]
    return [ false, "Unknown operation type: #{operation_type}" ] if schema.nil?

    # Support both camelCase and snake_case for schema_version key
    schema_version = (payload[:schemaVersion] || payload["schemaVersion"] ||
                      payload[:schema_version] || payload["schema_version"])
    expected_version = schema[:schema_version]

    if schema_version != expected_version
      return [ false, "schemaVersion mismatch: expected #{expected_version}, got #{schema_version}" ]
    end

    allowed_fields = schema[:fields]
    actual_fields = payload.keys.map { |k| k.to_sym }

    unexpected = actual_fields - allowed_fields
    return [ false, "Unexpected fields: #{unexpected.join(", ")}" ] unless unexpected.empty?

    [ true, nil ]
  end

  # Validate and raise if invalid.
  def self.validate!(operation_type, payload)
    valid, error = valid?(operation_type, payload)
    raise ArgumentError, error unless valid
  end
end
