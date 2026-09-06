# frozen_string_literal: true

# Suppression Gate — Annex I §21.2.
#
# An agent may fix code to satisfy a gate. It may not silence a rule to get past
# one. A suppression is therefore allowed, but never anonymous: it has to name a
# Story or an ADR and say why, on the same line or immediately above it.
#
# Without this, `# rubocop:disable` and `// eslint-disable-next-line` become the
# cheapest way to make any checker green, and the ruleset decays one commit at a
# time with nobody able to say when.
#
# See docs/engineering/lint-suppressions.md.
module Opanel
  module Gates
    class SuppressionGate
      Violation = Struct.new(:rule, :file, :line, :message, :remedy, keyword_init: true) do
        def to_h
          { rule: rule, file: file, line: line, message: message, remedy: remedy }
        end
      end

      RULE = "SUPPRESSION_JUSTIFIED"
      RULE_DESCRIPTION = "A silenced lint or security rule names the Story or ADR that allows it."

      # Every form of suppression this repository can express.
      SUPPRESSIONS = [
        /#\s*rubocop:disable\s+(?<rules>[\w\/,: ]+)/,
        /\/\/\s*eslint-disable(?:-next-line|-line)?\s*(?<rules>[@\w\/,\- ]*)/,
        /\/\*\s*eslint-disable(?:-next-line)?\s*(?<rules>[@\w\/,\- ]*)/,
        /#\s*nosec\b(?<rules>.*)/,
        /#\s*brakeman:ignore\b(?<rules>.*)/,
        /\/\/\s*@ts-(?:ignore|expect-error)(?<rules>.*)/
      ].freeze

      # A justification names a Story (M00-07), an ADR (ADR-0002), or an issue.
      JUSTIFICATION = /\b(M\d{2}-\d{2}|ADR-\d{4}|#\d+)\b/

      # `rubocop:enable` closes a block; it silences nothing on its own.
      IGNORED = /#\s*rubocop:enable|\/\*\s*eslint-enable|\/\/\s*eslint-enable/

      def self.check_paths(paths)
        paths.flat_map { |path| new(path).violations }
      end

      def initialize(path)
        @path = path.to_s
        # A repository holds fonts, images and PDFs. Reading them as text is not an
        # error to report — there is simply nothing there to suppress — so invalid
        # bytes are dropped rather than raised.
        @lines = File.read(@path, encoding: "BINARY")
          .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          .lines(chomp: true)
      rescue ArgumentError, Errno::EISDIR
        @lines = []
      end

      attr_reader :path

      def violations
        lines.each_with_index.filter_map do |line, index|
          next if line.match?(IGNORED)

          suppression = SUPPRESSIONS.find { |pattern| line.match?(pattern) }
          next unless suppression
          next if justified?(index)

          Violation.new(
            rule: RULE,
            file: path,
            line: index + 1,
            message: "rule suppressed without naming the Story or ADR that allows it",
            remedy: "add the reason and a reference on the same line or the line above, e.g. " \
                    "`# rubocop:disable Metrics/AbcSize -- M01-14: state machine reads better whole`. " \
                    "See docs/engineering/lint-suppressions.md"
          )
        end
      end

      private

      attr_reader :lines

      # The reference may sit on the suppression line itself or on the comment
      # directly above it, which is where a longer reason naturally goes.
      def justified?(index)
        return true if lines[index].match?(JUSTIFICATION)

        previous = index.positive? ? lines[index - 1].to_s : ""
        previous.match?(JUSTIFICATION) && previous.strip.match?(/\A(#|\/\/|\*)/)
      end
    end
  end
end
