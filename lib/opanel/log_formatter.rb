# frozen_string_literal: true

require "json"

module Opanel
  # One JSON object per line, with the correlation fields already attached.
  #
  # An operational failure has to be diagnosable from the log without reproducing
  # it locally (Annex I §19.2). That needs two things a plain string cannot give:
  # machine-readable fields, and the identifiers that tie a line to the request,
  # the operation and the tenant it belongs to.
  #
  # The correlation fields are read from `Current`, so a caller never has to
  # remember to pass them. Every field the following Milestones will fill —
  # `operation_id`, the tenancy chain, the actor — is already part of the contract:
  # they appear when set and are omitted when not, so nothing about this formatter
  # changes when M01 starts setting them.
  #
  # **Redaction happens here, at the sink.** Code that knows a value is a secret
  # must not log it, but that discipline fails eventually — a driver interpolates a
  # connection string into an exception, a middleware dumps a header. This is the
  # last barrier (Annex C §17.1).
  class LogFormatter < ::Logger::Formatter
    # Always present, in this order, so a line is readable without a parser.
    BASE_FIELDS = %i[timestamp level message].freeze

    # Reserved for the Milestones that own them. Declared here so the contract is
    # visible now and does not change when they start being set.
    CORRELATION_FIELDS = %i[
      request_id
      correlation_id
      operation_id
      team_id
      project_id
      environment_id
      service_id
      cluster_id
      node_id
      actor_id
      source
    ].freeze

    def call(severity, time, progname, message)
      payload = {
        timestamp: time.utc.iso8601(3),
        level: severity.to_s.downcase,
        **fields_from(message),
        **correlation_fields,
        source: progname.presence || correlation_source
      }.compact

      "#{JSON.generate(Redaction.apply(payload))}\n"
    rescue StandardError => error
      # A logger that raises takes the request with it, and the original message
      # is lost along with whatever it was about to explain. Falling back keeps
      # the line — and says why it is not structured.
      fallback(severity, time, message, error)
    end

    private

    # A Hash message becomes fields; anything else becomes `message`.
    def fields_from(message)
      case message
      when Hash then normalize(message)
      when Exception then { message: message.message, error_class: message.class.name }
      else { message: message.to_s.strip }
      end
    end

    def normalize(hash)
      hash.to_h { |key, value| [ key.to_sym, value ] }
    end

    def correlation_fields
      return {} unless defined?(::Current)

      CORRELATION_FIELDS.each_with_object({}) do |field, fields|
        next unless ::Current.respond_to?(field)

        value = ::Current.public_send(field)
        fields[field] = value if value.present?
      end
    end

    def correlation_source
      "opanel"
    end

    def fallback(severity, time, message, error)
      payload = {
        timestamp: time.utc.iso8601(3),
        level: severity.to_s.downcase,
        message: Redaction.apply(message.to_s),  # may raise; the inner rescue covers it
        source: "opanel",
        log_formatter_error: error.class.name
      }

      "#{JSON.generate(payload)}\n"
    rescue StandardError
      # The message itself cannot be rendered — `to_s` raised. Emitting the
      # severity and the reason is still better than losing the line and the
      # knowledge that something tried to log here.
      "#{JSON.generate(level: severity.to_s.downcase, source: 'opanel',
                       message: '[UNRENDERABLE]', log_formatter_error: error.class.name)}\n"
    end
  end
end
