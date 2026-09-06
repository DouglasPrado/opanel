# frozen_string_literal: true

require "yaml"
require "date"

# Security waivers — Annex D §24.1, Annex I §16.3.
#
# A finding can be accepted. It cannot be accepted **forever**, and it cannot be
# accepted **anonymously**. Every waiver names the risk, the person who owns it,
# why it is acceptable, what mitigates it, and the date it stops being acceptable.
#
# **An expired waiver blocks again, automatically.** That is the whole mechanism:
# without it a waiver file becomes a list of things nobody has looked at since,
# and the scanner it silences becomes decoration.
#
# The agent cannot waive its way past a gate — a waiver has an owner, and the
# owner is a person.
module Opanel
  module Gates
    class SecurityWaivers
      REQUIRED_FIELDS = %w[id tool finding risk owner justification mitigation expires_at].freeze

      # Waiving these needs recorded human approval: they are the controls that
      # exist because their absence is how a platform leaks (Annex I §16.3).
      HUMAN_APPROVAL_REQUIRED = %w[secret-scan].freeze

      # UTC, not the machine's local date. An expiry that depends on which
      # timezone the check runs in means CI and a developer disagree about
      # whether a waiver is still valid — and the disagreement lasts three hours
      # a day. Not `Date.current`: this file loads without Rails, because
      # bin/security-waivers runs standalone.
      def self.today = Time.now.utc.to_date

      Waiver = Struct.new(:id, :tool, :finding, :risk, :owner, :justification, :mitigation,
        :expires_at, :approved_by, keyword_init: true) do
        def expired?(today = SecurityWaivers.today)
          Date.parse(expires_at.to_s) < today
        end

        def days_left(today = SecurityWaivers.today)
          (Date.parse(expires_at.to_s) - today).to_i
        end

        def to_h
          super.merge(expired: expired?)
        end
      end

      class InvalidWaiver < StandardError; end

      def self.load(path)
        return new([]) unless File.exist?(path)

        document = YAML.safe_load_file(path, permitted_classes: [ Date ]) || {}
        new(Array(document["waivers"]).map { |entry| build(entry) })
      end

      def self.build(entry)
        missing = REQUIRED_FIELDS.reject { |field| entry[field].to_s.strip != "" }

        unless missing.empty?
          raise InvalidWaiver,
            "waiver #{entry['id'] || '(no id)'} is missing #{missing.join(', ')} — " \
            "a waiver without an owner and an expiry is a permanent silence"
        end

        begin
          Date.parse(entry["expires_at"].to_s)
        rescue ArgumentError
          raise InvalidWaiver, "waiver #{entry['id']} has an unparseable expires_at"
        end

        if HUMAN_APPROVAL_REQUIRED.include?(entry["tool"].to_s) && entry["approved_by"].to_s.strip.empty?
          raise InvalidWaiver,
            "waiver #{entry['id']} silences #{entry['tool']}, which needs recorded human approval " \
            "(approved_by) — an agent may not waive it"
        end

        Waiver.new(**entry.transform_keys(&:to_sym).slice(*Waiver.members))
      end

      def initialize(waivers)
        @waivers = waivers
      end

      attr_reader :waivers

      def active(today = self.class.today)
        waivers.reject { |waiver| waiver.expired?(today) }
      end

      def expired(today = self.class.today)
        waivers.select { |waiver| waiver.expired?(today) }
      end

      # A finding is silenced only by a waiver that is still in date.
      def waives?(tool, finding, today = self.class.today)
        active(today).any? { |waiver| waiver.tool == tool.to_s && waiver.finding == finding.to_s }
      end

      # Anything within a fortnight, so a waiver is renewed or fixed deliberately
      # rather than discovered on the morning it starts blocking the build.
      def expiring_soon(today = self.class.today, within: 14)
        active(today).select { |waiver| waiver.days_left(today) <= within }
      end
    end
  end
end
