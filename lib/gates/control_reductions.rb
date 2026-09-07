# frozen_string_literal: true

require "json"

require_relative "security_waivers"

module Opanel
  module Gates
    # Controls this repository has turned down, and the waivers that allow it.
    #
    # The Suppression Gate covers a rule silenced on a *line*: the comment has to
    # name the Story or ADR that allows it. A control turned down in a
    # *configuration* file leaves no such line — `'jsx-a11y/anchor-has-content':
    # 'off'` for a whole directory, a tsconfig flag simply left out, an
    # accessibility violation added to a baseline. Each of those was justified by
    # a comment the implementer wrote, and a comment is not the exception
    # process: Annex I §16.3 and Annex D §24.1 require an owner, a risk, a
    # mitigation and the date the exception stops being acceptable.
    #
    # Same contract as the security waivers, so there is one shape to learn — and
    # the property that matters is the same one: **an expired waiver blocks
    # again**. Without it the file becomes a list nobody has looked at since, and
    # the controls it covers are off permanently by accident.
    class ControlReductions
      Violation = Struct.new(:rule, :file, :line, :message, :remedy, keyword_init: true) do
        def to_h = { rule: rule, file: file, line: line, message: message, remedy: remedy }
      end

      RULE = "CONTROL_WAIVED"
      RULE_DESCRIPTION = "A control turned down in configuration has an owned, dated waiver."

      WAIVERS = "config/quality/waivers.yml"

      # The TypeScript strictness this repository holds itself to. A flag that is
      # absent or false is a reduction — including the two that `strict` does not
      # imply, because leaving them out was a decision and decisions expire.
      TYPESCRIPT_FLAGS = %w[
        strict noImplicitOverride noFallthroughCasesInSwitch noUnusedLocals
        noUnusedParameters verbatimModuleSyntax isolatedModules
        exactOptionalPropertyTypes noUncheckedIndexedAccess
      ].freeze

      TSCONFIG = "tsconfig.json"
      ESLINT_CONFIG = "eslint.config.js"
      ACCESSIBILITY_BASELINE = "e2e/accessibility-baseline.json"

      # `'rule/name': 'off'` — written here, not inherited from a shared config.
      #
      # `%r{}` because the rule names contain `/`, and a `/` inside a character
      # class still closes a `/.../` literal: Ruby lexes the delimiter before it
      # ever parses the class.
      #
      # Not anchored to the start of a line. A rule turned down is turned down
      # whether the object is written one key per line or all on one — anchoring
      # would make the check a property of the formatter.
      ESLINT_OFF = %r{(?<![\w'"])['"]([@\w./-]+)['"]\s*:\s*['"]off['"]}

      def initialize(root = Dir.pwd)
        @root = root
        @waiver_error = nil

        begin
          @waivers = SecurityWaivers.load(File.join(root, WAIVERS))
        rescue SecurityWaivers::InvalidWaiver => error
          # A malformed waiver is not a waiver, so nothing it claims to cover is
          # covered. Reported rather than raised, so the reason reaches the same
          # place every other finding does.
          @waivers = SecurityWaivers.new([])
          @waiver_error = error.message
        end
      end

      attr_reader :root, :waivers

      def violations
        malformed_waiver_violations + expired_waiver_violations + typescript_violations +
          eslint_violations + accessibility_violations
      end

      private

      def malformed_waiver_violations
        return [] if @waiver_error.nil?

        [ violation(WAIVERS, nil, @waiver_error,
          "a waiver missing a field is not a waiver, and everything it claimed to cover is " \
          "blocking again until it is complete") ]
      end

      # An expired waiver is itself a finding, and says so by name rather than
      # only by the control silently blocking again.
      def expired_waiver_violations
        waivers.expired.map do |waiver|
          violation(WAIVERS, nil,
            "waiver #{waiver.id} for #{waiver.tool}/#{waiver.finding} expired on #{waiver.expires_at}",
            "restore the control, or renew the waiver deliberately with a new date and a reason " \
            "the renewal is justified — that decision belongs to #{waiver.owner}")
        end
      end

      def typescript_violations
        options = tsconfig.fetch("compilerOptions", {})

        TYPESCRIPT_FLAGS.reject { |flag| options[flag] == true }
          .reject { |flag| waivers.waives?("typescript", flag) }
          .map do |flag|
            violation(TSCONFIG, nil,
              "`#{flag}` is not enabled",
              "turn it on, or record a waiver in #{WAIVERS} with `tool: typescript`, " \
              "`finding: #{flag}`, an owner and an expiry")
          end
      end

      def eslint_violations
        return [] unless File.exist?(path(ESLINT_CONFIG))

        # Every match on the line, not the first: one line can turn several rules
        # down, and reporting one of them is reporting that the line was read.
        File.readlines(path(ESLINT_CONFIG)).each_with_index.flat_map do |line, index|
          line.scan(ESLINT_OFF).flatten.reject { |rule| waivers.waives?("eslint", rule) }.map do |rule|
            violation(ESLINT_CONFIG, index + 1,
              "`#{rule}` is turned off",
              "fix the code, or record a waiver in #{WAIVERS} with `tool: eslint`, " \
              "`finding: #{rule}`, an owner and an expiry")
          end
        end
      end

      def accessibility_violations
        return [] unless File.exist?(path(ACCESSIBILITY_BASELINE))

        baseline = JSON.parse(File.read(path(ACCESSIBILITY_BASELINE))).fetch("violations", {})

        baseline.keys.reject { |id| waivers.waives?("accessibility", id) }.map do |id|
          violation(ACCESSIBILITY_BASELINE, nil,
            "`#{id}` is baselined, so the WCAG 2.2 AA gate does not block on it",
            "fix it upstream and remove the entry, or record a waiver in #{WAIVERS} with " \
            "`tool: accessibility`, `finding: #{id}`, an owner and an expiry")
        end
      end

      # tsconfig.json is JSON with comments. Stripping whole comment lines is
      # enough for this file and keeps a parser out of the dependency list.
      def tsconfig
        return {} unless File.exist?(path(TSCONFIG))

        JSON.parse(File.readlines(path(TSCONFIG)).reject { |line| line.strip.start_with?("//") }.join)
      rescue JSON::ParserError => error
        raise "#{TSCONFIG} could not be read: #{error.message}"
      end

      def path(relative) = File.join(root, relative)

      def violation(file, line, message, remedy)
        Violation.new(rule: RULE, file: file, line: line, message: message, remedy: remedy)
      end
    end
  end
end
