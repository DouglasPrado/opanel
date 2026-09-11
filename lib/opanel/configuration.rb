# frozen_string_literal: true

module Opanel
  # The configuration contract of the installation.
  #
  # Every key the application reads from the environment is declared here, with
  # where it is required, what shape it must have, and whether it is a credential.
  # Nothing reads an undeclared key: a value that is not in this list cannot be
  # relied on, and one that is missing cannot be discovered at three in the
  # morning.
  #
  # **Missing configuration fails closed.** A default exists only where the
  # default is safe — a port, a pool size, a local database name. It never exists
  # for a credential, a host boundary or anything that grants access, because a
  # permissive default is how an installation ends up open by accident
  # (Annex I §2, "Secure by default").
  #
  # **An error never prints the value it received.** It names the key and states
  # the expected shape. A malformed password is still a password (Annex C §17.1).
  class Configuration
    class InvalidConfiguration < StandardError
      attr_reader :problems

      def initialize(problems)
        @problems = problems
        super(problems.join("\n"))
      end
    end

    FORMATS = {
      integer: {
        matcher: ->(value) { value.match?(/\A\d+\z/) },
        expected: "a non-negative integer"
      },
      number: {
        matcher: ->(value) { value.match?(/\A\d+(\.\d+)?\z/) },
        expected: "a non-negative number"
      },
      hostname: {
        matcher: ->(value) { value.match?(/\A[A-Za-z0-9._\-:\[\]]+\z/) },
        expected: "a hostname or IP address"
      },
      # 128 bits of entropy at minimum, hex or base64.
      secret: {
        matcher: ->(value) { value.length >= 32 },
        expected: "at least 32 characters"
      },
      supervisor_mode: {
        matcher: ->(value) { %w[fork async].include?(value) },
        expected: "fork or async"
      },
      free_text: {
        matcher: ->(value) { !value.strip.empty? },
        expected: "a non-empty value"
      }
    }.freeze

    Key = Struct.new(:name, :required_in, :format, :default, :sensitive, :description, keyword_init: true) do
      def required?(environment) = Array(required_in).include?(environment.to_s)
      def sensitive? = sensitive == true
    end

    KEYS = [
      Key.new(
        name: "SECRET_KEY_BASE",
        required_in: %w[production ci],
        format: :secret,
        sensitive: true,
        description: "Signs cookies and message verifiers. Development and test use a Rails-generated " \
                     "local secret; every other environment must supply one."
      ),
      Key.new(
        name: "OPANEL_DATABASE_HOST",
        required_in: %w[production],
        format: :hostname,
        default: "localhost",
        description: "PostgreSQL host."
      ),
      Key.new(
        name: "OPANEL_DATABASE_PORT",
        required_in: [],
        format: :integer,
        default: "5432",
        description: "PostgreSQL port."
      ),
      Key.new(
        name: "OPANEL_DATABASE_NAME",
        required_in: %w[production],
        format: :free_text,
        default: nil,
        description: "Database name. Each environment defaults to its own in config/database.yml."
      ),
      Key.new(
        name: "OPANEL_DATABASE_USERNAME",
        required_in: %w[production],
        format: :free_text,
        description: "PostgreSQL role. Blank locally means the operating-system user."
      ),
      Key.new(
        name: "OPANEL_DATABASE_PASSWORD",
        required_in: %w[production],
        format: :free_text,
        sensitive: true,
        description: "PostgreSQL password. Never written to a versioned file."
      ),
      Key.new(
        name: "OPANEL_DATABASE_MAX_CONNECTIONS",
        required_in: [],
        format: :integer,
        default: nil,
        description: "Connection pool size. Defaults to RAILS_MAX_THREADS."
      ),
      Key.new(
        name: "OPANEL_DATABASE_CHECKOUT_TIMEOUT",
        required_in: [],
        format: :integer,
        default: "5",
        description: "Seconds a request waits for a connection before failing deterministically."
      ),
      Key.new(
        name: "RAILS_MAX_THREADS",
        required_in: [],
        format: :integer,
        default: "3",
        description: "Puma threads per worker, and the default connection pool size."
      ),
      Key.new(
        name: "OPANEL_JOB_CONCURRENCY",
        required_in: [],
        format: :integer,
        default: "1",
        description: "Worker processes for the deployments and runtime queues."
      ),
      Key.new(
        name: "OPANEL_JOB_SUPERVISOR_MODE",
        required_in: [],
        format: :supervisor_mode,
        default: nil,
        description: "fork or async. Defaults by platform — see bin/jobs."
      ),
      Key.new(
        name: "OPANEL_JOB_HEARTBEAT_INTERVAL_SECONDS",
        required_in: [],
        format: :number,
        default: "60",
        description: "How often a worker records that it is alive."
      ),
      Key.new(
        name: "OPANEL_JOB_ALIVE_THRESHOLD_SECONDS",
        required_in: [],
        format: :number,
        default: "300",
        description: "How long a worker may go silent before its claimed jobs are released."
      ),
      Key.new(
        name: "OPANEL_OUTBOX_DISPATCHER_BATCH_SIZE",
        required_in: [],
        format: :integer,
        default: "100",
        description: "Maximum number of outbox events to publish in one dispatcher run."
      ),
      Key.new(
        name: "OPANEL_OUTBOX_DISPATCHER_CADENCE_SECONDS",
        required_in: [],
        format: :number,
        default: "5",
        description: "How often the outbox dispatcher publishes pending events to the queue."
      ),
      Key.new(
        name: "OPANEL_RECOVERY_SWEEP_BATCH_SIZE",
        required_in: [],
        format: :integer,
        default: "50",
        description: "Maximum number of stalled operations to recover per sweep run."
      ),
      Key.new(
        name: "OPANEL_RECOVERY_SWEEP_CADENCE_SECONDS",
        required_in: [],
        format: :number,
        default: "30",
        description: "How often the recovery sweep checks for stalled operations."
      ),
      Key.new(
        name: "OPANEL_RECOVERY_SWEEP_HEARTBEAT_THRESHOLD_SECONDS",
        required_in: [],
        format: :number,
        default: "600",
        description: "How long a RUNNING operation may go without heartbeat before marked stalled (10 minutes)."
      ),
      Key.new(
        name: "OPANEL_RECOVERY_SWEEP_QUEUED_THRESHOLD_SECONDS",
        required_in: [],
        format: :number,
        default: "300",
        description: "How long a QUEUED operation may wait before marked stalled (5 minutes)."
      ),
      Key.new(
        name: "OPANEL_QUEUE_BACKPRESSURE_HIGH_WATER_MARK",
        required_in: [],
        format: :integer,
        default: "1000",
        description: "Number of unpublished events that triggers backpressure (deferral of new operations)."
      ),
      Key.new(
        name: "OPANEL_QUEUE_BACKPRESSURE_DELAY_SECONDS",
        required_in: [],
        format: :number,
        default: "60",
        description: "How long to defer operation enqueue when queue backpressure is active."
      )
    ].freeze

    def self.find(name) = KEYS.find { |key| key.name == name }

    def self.validate!(environment: Rails.env, source: ENV)
      problems = validate(environment: environment, source: source)
      raise InvalidConfiguration, problems unless problems.empty?

      true
    end

    # Returns a list of human-readable problems. Never includes a received value.
    def self.validate(environment: Rails.env, source: ENV)
      KEYS.filter_map { |key| problem_for(key, environment.to_s, source) }
    end

    def self.problem_for(key, environment, source)
      raw = source[key.name]
      value = raw.to_s.strip

      if value.empty?
        return nil unless key.required?(environment)

        return "#{key.name} is required in #{environment} and is not set. " \
               "Expected #{FORMATS.fetch(key.format)[:expected]}. #{key.description}"
      end

      return nil if FORMATS.fetch(key.format)[:matcher].call(value)

      # The value itself is never echoed: a malformed password is still a password.
      "#{key.name} is set but has an invalid format. Expected #{FORMATS.fetch(key.format)[:expected]}."
    end

    # The keys that carry credentials, so a report or a log can exclude them
    # without maintaining a second list.
    def self.sensitive_names = KEYS.select(&:sensitive?).map(&:name)

    # `EX_CONFIG` from sysexits(3). A supervisor, a runbook and RB-01 can tell
    # "the configuration is wrong" apart from "the code crashed" — different
    # incidents with different responses.
    EXIT_CODE = 78

    # Called from config/application.rb, before the application class is defined:
    # a configuration failure has to stop the boot, not surface on the first
    # request that happens to need the missing key.
    def self.validate_or_abort!(environment:, source: ENV, output: $stderr)
      problems = validate(environment: environment, source: source)
      return true if problems.empty?

      output.puts(abort_message(environment, problems))
      exit EXIT_CODE
    end

    def self.abort_message(environment, problems)
      [
        "",
        "Opanel cannot start: the configuration for the #{environment} environment is invalid.",
        "",
        *problems.map { |problem| "  - #{problem}" },
        "",
        "See .env.example for every key and the shape it must have. Credentials come",
        "from the environment; Opanel reads none from a versioned file.",
        ""
      ].join("\n")
    end

    # Convenience accessors for M01-14 outbox and recovery configuration.
    def self.outbox_dispatcher_batch_size
      ENV.fetch("OPANEL_OUTBOX_DISPATCHER_BATCH_SIZE", "100").to_i
    end

    def self.outbox_dispatcher_cadence_seconds
      ENV.fetch("OPANEL_OUTBOX_DISPATCHER_CADENCE_SECONDS", "5").to_i
    end

    def self.recovery_sweep_batch_size
      ENV.fetch("OPANEL_RECOVERY_SWEEP_BATCH_SIZE", "50").to_i
    end

    def self.recovery_sweep_cadence_seconds
      ENV.fetch("OPANEL_RECOVERY_SWEEP_CADENCE_SECONDS", "30").to_i
    end

    def self.recovery_sweep_heartbeat_threshold
      Time.current.utc - ENV.fetch("OPANEL_RECOVERY_SWEEP_HEARTBEAT_THRESHOLD_SECONDS", "600").to_i.seconds
    end

    def self.recovery_sweep_queued_threshold
      Time.current.utc - ENV.fetch("OPANEL_RECOVERY_SWEEP_QUEUED_THRESHOLD_SECONDS", "300").to_i.seconds
    end

    def self.queue_backpressure_high_water_mark
      ENV.fetch("OPANEL_QUEUE_BACKPRESSURE_HIGH_WATER_MARK", "1000").to_i
    end

    def self.queue_backpressure_delay_seconds
      ENV.fetch("OPANEL_QUEUE_BACKPRESSURE_DELAY_SECONDS", "60").to_i
    end
  end
end
