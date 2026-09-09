# frozen_string_literal: true

require "securerandom"

module Opanel
  # The platform's one identifier format — ADR-0002.
  #
  # A ULID: 48 bits of millisecond timestamp followed by 80 bits of entropy,
  # rendered as 26 Crockford Base32 characters. It is lexicographically ordered
  # by time, which keeps B-tree locality in the high-volume tables without
  # exposing a predictable sequence, and it is generated in the application, so a
  # single transaction can build a whole object graph without a round trip.
  #
  # **The identity is the ULID. The prefix is presentation.** `usr_01HX…` is what
  # the API, the UI, the MCP resource URIs, the events and the Swarm labels carry;
  # the column holds the bare 26 characters.
  #
  # Required directly from config/application.rb, before Zeitwerk, for the same
  # reason as Opanel::Configuration: the prefix registry is validated on every
  # boot in every environment, so a duplicate prefix is a boot error rather than a
  # runtime surprise on the one route that uses it.
  module Identifier
    class Error < StandardError; end

    # Two types resolving to one prefix makes an identifier ambiguous in a log,
    # in an audit record and in a Swarm label. ADR-0002 §3 makes it a boot error.
    class DuplicatePrefixError < Error; end

    # A type that has no registered prefix. Registering one is what ADR-0002 §3
    # requires of a new entity, and forgetting has to fail loudly rather than
    # produce `_01HX…`.
    class UnknownType < Error; end

    # ADR-0002 §4: an identifier carrying another type's prefix is a validation
    # failure, never a NOT_FOUND. Answering NOT_FOUND would turn type confusion
    # into an existence oracle.
    #
    # **This is a shape check and nothing more.** It does not replace the tenancy
    # check of Annex C §7.3, which is independent and still mandatory.
    class InvalidIdentifier < Error
      def code = "VALIDATION_ERROR"
    end

    # Crockford Base32: no I, L, O or U, so a human reading an id aloud or
    # copying it from a terminal cannot produce a different one.
    ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    LENGTH = 26
    PATTERN = /\A[0-9A-HJKMNP-TV-Z]{26}\z/
    TIMESTAMP_BITS = 48
    ENTROPY_BITS = 80
    MAX_ENTROPY = (1 << ENTROPY_BITS) - 1
    MAX_TIMESTAMP = (1 << TIMESTAMP_BITS) - 1

    # The registry of ADR-0002 §3. `ses` is registered here for Session under the
    # ADR's own rule that a new type registers its prefix; everything else is the
    # list the ADR writes out.
    PREFIXES = {
      user: "usr",
      team: "team",
      # Registered here under the same rule as `ses`: ADR-0002 §3 requires a new
      # entity to register its prefix, and a membership is addressable — it is
      # what a suspension, a role change and an ownership transfer name.
      team_member: "tm",
      # Same rule again (ADR-0002 §3). An instance role is addressable because a
      # grant and its revocation name one, and the audit record of M01-05 has to
      # say which grant was revoked.
      instance_role: "iro",
      project: "prj",
      environment: "env",
      service: "svc",
      release: "rel",
      artifact: "art",
      build: "bld",
      deployment: "dep",
      operation: "op",
      secret: "sec",
      secret_version: "sv",
      domain: "dom",
      certificate: "cert",
      certificate_version: "cv",
      cluster: "cl",
      node: "node",
      enrollment: "enr",
      backup: "bkp",
      snapshot: "snap",
      restore: "rst",
      approval: "apr",
      agent_conversation: "agc",
      token: "tok",
      incident: "inc",
      alert: "alr",
      session: "ses"
    }.freeze

    SEPARATOR = "_"

    MUTEX = Mutex.new

    @last_timestamp = nil
    @last_entropy = nil

    class << self
      # A new ULID, monotonic within a millisecond.
      #
      # When the clock has not moved the entropy is **incremented** rather than
      # redrawn (ADR-0002 §1). Redrawing would make two ids created in the same
      # millisecond sort arbitrarily, which silently breaks keyset pagination and
      # any "most recent first" ordering that trusts the key.
      def generate
        MUTEX.synchronize do
          now = current_milliseconds

          if now == @last_timestamp && !@last_entropy.nil? && @last_entropy < MAX_ENTROPY
            @last_entropy += 1
          else
            @last_timestamp = now
            @last_entropy = SecureRandom.random_number(MAX_ENTROPY + 1)
          end

          encode(@last_timestamp, @last_entropy)
        end
      end

      # The external representation: `usr_01HX8Z9K3M4P5Q6R7S8T9V0W1X`.
      def external(type, id)
        prefix = prefix_for(type)
        return nil if id.nil?

        "#{prefix}#{SEPARATOR}#{id}"
      end

      # The bare ULID behind an external identifier of the expected type.
      def parse(type, value)
        expected = prefix_for(type)
        text = value.to_s

        prefix, _, id = text.partition(SEPARATOR)

        if prefix.empty? || id.empty?
          raise InvalidIdentifier, "expected an identifier of the form #{expected}#{SEPARATOR}<ulid>"
        end

        unless prefix == expected
          # Deliberately says which type was expected and never whether the id
          # exists.
          raise InvalidIdentifier, "expected a #{expected}#{SEPARATOR} identifier"
        end

        raise InvalidIdentifier, "malformed identifier" unless id.match?(PATTERN)

        id
      end

      def prefix_for(type)
        PREFIXES.fetch(type.to_sym) do
          raise UnknownType, "no prefix is registered for #{type.inspect} — ADR-0002 §3 requires one"
        end
      end

      # Called from config/application.rb, so a collision stops the boot.
      def validate_registry!(registry = PREFIXES)
        seen = {}

        registry.each do |type, prefix|
          if seen.key?(prefix)
            raise DuplicatePrefixError,
              "prefix #{prefix.inspect} is registered for both #{seen[prefix].inspect} and " \
              "#{type.inspect} — an identifier that could mean either is ambiguous everywhere " \
              "it is written (ADR-0002 §3)"
          end

          seen[prefix] = type
        end

        true
      end

      private

      def current_milliseconds
        (Time.now.utc.to_f * 1000).floor.clamp(0, MAX_TIMESTAMP)
      end

      def encode(timestamp, entropy)
        value = (timestamp << ENTROPY_BITS) | entropy
        characters = Array.new(LENGTH)

        (LENGTH - 1).downto(0) do |index|
          characters[index] = ALPHABET[value & 0x1F]
          value >>= 5
        end

        characters.join
      end
    end
  end
end
