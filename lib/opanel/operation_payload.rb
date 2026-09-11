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

  # Event type schemas: allowlist of known OutboxEvent types and their versions (AC8, M01-14).
  #
  # This is separate from operation payloads but related: Operations generate OutboxEvents.
  # An OutboxEvent carries an event_type and schema_version, which the dispatcher
  # validates before publishing. An unknown event type → unknown schema_version → skip and log.
  #
  # Event types are domain-oriented (service.desired_state.changed.v1) and version the
  # logical event, not the operation type. Multiple operation types may emit the same event.
  EVENT_SCHEMAS = {
    "service.desired_state.changed.v1" => {
      schema_version: 1,
      fields: %i[
        schemaVersion
        service_id
        environment_id
        project_id
        team_id
        desired_revision
        changes
        timestamp
      ].freeze
    },
    "service.deployed.v1" => {
      schema_version: 1,
      fields: %i[
        schemaVersion
        service_id
        release_id
        image_digest
        timestamp
      ].freeze
    }
  }.freeze

  # Validate an OutboxEvent's schema (dispatcher, AC8).
  # Checks both the column schema_version and the payload's schemaVersion field.
  # @param event_type [String] the event type (e.g., "service.desired_state.changed.v1")
  # @param schema_version [Integer] the column schema_version
  # @param payload [Hash, optional] the event payload (to validate payload.schemaVersion against column)
  # @return [Array] [valid?, error_message]
  def self.event_valid?(event_type, schema_version, payload = nil)
    schema = EVENT_SCHEMAS[event_type]
    return [ false, "Unknown event type: #{event_type}" ] if schema.nil?

    if schema_version != schema[:schema_version]
      return [ false,
"schemaVersion mismatch for #{event_type}: expected #{schema[:schema_version]}, got #{schema_version}" ]
    end

    # If payload is provided, validate that its schemaVersion matches the column.
    if payload.present?
      payload_version = (payload[:schemaVersion] || payload["schemaVersion"])
      if payload_version.present? && payload_version != schema_version
        return [ false,
"Payload schemaVersion #{payload_version} disagrees with column schema_version #{schema_version}" ]
      end
    end

    [ true, nil ]
  end

  # Validate an OutboxEvent's schema and raise if invalid.
  def self.event_validate!(event_type, schema_version)
    valid, error = event_valid?(event_type, schema_version)
    raise ArgumentError, error unless valid
  end
end
