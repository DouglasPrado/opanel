# frozen_string_literal: true

module Opanel
  # Classifies PostgreSQL connectivity so a failure names its cause instead of
  # surfacing as a generic timeout, and so no credential survives the trip to a
  # log, an error message or a health response.
  #
  # The same classification feeds the readiness endpoint in M00-15 and matches what
  # runbook RB-02 expects an operator to read during an incident.
  module DatabaseConnection
    Result = Struct.new(:cause, :detail, keyword_init: true) do
      def available? = cause == :available
    end

    CAUSES = %i[
      available
      authentication_failed
      database_missing
      host_unreachable
      timeout
      configuration_invalid
      unknown
    ].freeze

    # Ordered: the first pattern that matches wins, so the specific causes are
    # listed before the generic connection failure.
    CLASSIFIERS = [
      [ :authentication_failed, /password authentication failed|no pg_hba\.conf entry|role .* does not exist/i ],
      [ :database_missing, /database .* does not exist/i ],
      [ :timeout, /timeout expired|could not receive data from server|statement timeout/i ],
      [ :host_unreachable, /could not connect to server|connection refused|could not translate host name|no such file or directory|is the server running/i ],
      [ :configuration_invalid, /invalid (connection option|integer value)|missing .* configuration/i ]
    ].freeze

    # Secrets never reach a log, an exception or a response (Annex C §17.1). PG
    # error text can carry a full connection URI, so redaction happens here, at the
    # boundary that knows the shape of the value.
    REDACTIONS = [
      [ /(\bpassword\s*=\s*)(\S+)/i, '\1[REDACTED]' ],
      [ %r{(\b[a-z][a-z0-9+.-]*://[^\s:/@]+:)([^\s@]+)(@)}i, '\1[REDACTED]\3' ],
      [ /("?PG(?:PASSWORD|PASS)"?\s*[:=]\s*)(\S+)/i, '\1[REDACTED]' ]
    ].freeze

    module_function

    # Runs the cheapest possible query against the pool and reports what happened.
    def check(pool = ActiveRecord::Base.connection_pool)
      pool.with_connection { |connection| connection.select_value("SELECT 1") }
      Result.new(cause: :available, detail: nil)
    rescue StandardError => error
      # Broad by design, and it does not hide the failure: the caller receives a
      # Result that is not `available?` and carries the classified cause. This is
      # the opposite of the generic rescue that returns success (Annex I §7.1).
      classify(error)
    end

    def classify(error)
      message = redact(error.message.to_s)

      # Active Record rewrites the adapter's message ("Database not found: x"), so
      # the original PostgreSQL wording lives in the cause chain. Both are searched:
      # the wording is the specific signal, the exception class is the fallback.
      searchable = redact(message_chain(error))

      cause = CLASSIFIERS.find { |_name, pattern| searchable.match?(pattern) }&.first
      cause ||= classify_by_class(error)
      cause ||= :unknown

      Result.new(cause: cause, detail: "#{error.class}: #{first_line(message)}")
    end

    def classify_by_class(error)
      case error
      when ActiveRecord::ConnectionTimeoutError then :timeout
      when ActiveRecord::NoDatabaseError then :database_missing
      when ActiveRecord::DatabaseConnectionError, ActiveRecord::ConnectionNotEstablished then :host_unreachable
      end
    end

    def message_chain(error)
      messages = []
      current = error
      seen = 0

      while current && seen < 5
        messages << current.message.to_s
        current = current.cause
        seen += 1
      end

      messages.join("\n")
    end

    # Removes credential material from a message before anyone can log it.
    def redact(message)
      REDACTIONS.reduce(message) { |text, (pattern, replacement)| text.gsub(pattern, replacement) }
    end

    # PG stitches the whole connection attempt into one multi-line message. Only the
    # first line carries the cause; the rest repeats host and port permutations.
    def first_line(message)
      message.lines.first.to_s.strip
    end
  end
end
