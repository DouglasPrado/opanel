# frozen_string_literal: true

require "json"

module Opanel
  module Gates
    # A Story's implementation self-review, read rather than assumed.
    #
    # `Critical = 0` and `High = 0` block DONE and block merge (Annex I §17.1).
    # Both the Post-commit Gate and the Stop Gate used to establish that by
    # globbing `docs/implementation/<M>/review/*.json` — of which this repository
    # has none. Eighteen Markdown reviews sat next to that glob, none were read,
    # and every Story reported zero blocking findings. A Milestone with no review
    # file at all reported the same thing.
    #
    # So: the canonical form is the Markdown of docs/templates/REVIEW_FINDINGS.md,
    # JSON is accepted for a machine-produced review, and **an absent review is a
    # failure**, not an empty list. A check satisfied by writing nothing is worse
    # than no check.
    module ReviewFindings
      BLOCKING_SEVERITIES = %w[critical high].freeze
      RESOLVED_STATES = %w[closed resolved fixed].freeze

      Finding = Struct.new(:id, :severity, :title, :state, :file, keyword_init: true) do
        def blocking? = BLOCKING_SEVERITIES.include?(severity.to_s) && !resolved?

        # `- **Estado:** closed`, or a severity annotated `(resolved)`. Both say
        # the finding was dealt with inside the Story rather than carried out of
        # it.
        def resolved? = RESOLVED_STATES.include?(state.to_s)

        def to_s = "#{id}: #{severity} — #{title}"
      end

      # `### F-1 — <title>`
      HEADING = /^###\s+(?<id>F-\d+)\s*(?:—|-|–)?\s*(?<title>.*)$/
      SEVERITY = /^\s*[-*]\s*\*\*Severidade:\*\*\s*(?<severity>[A-Za-z]+)(?<qualifier>.*)$/
      STATE = /^\s*[-*]\s*\*\*Estado:\*\*\s*(?<state>[A-Za-z]+)/
      RESOLVED_QUALIFIER = /resolv/i

      module_function

      # Both extensions, so neither form can be the one nobody looks for.
      def paths(directory, story)
        Dir.glob(File.join(directory, "#{story}.{md,json}")).sort
      end

      def missing?(directory, story) = paths(directory, story).empty?

      def for_story(directory, story)
        paths(directory, story).flat_map { |path| parse(path) }
      end

      def blocking(directory, story)
        for_story(directory, story).select(&:blocking?)
      end

      def parse(path)
        path.end_with?(".json") ? parse_json(path) : parse_markdown(path)
      end

      def parse_markdown(path)
        findings = []
        current = nil

        File.read(path).each_line do |line|
          if (heading = line.match(HEADING))
            current = Finding.new(id: heading[:id], title: heading[:title].strip, file: path)
            findings << current
            next
          end

          next if current.nil?

          if (severity = line.match(SEVERITY))
            current.severity = severity[:severity].downcase
            current.state = "resolved" if severity[:qualifier].match?(RESOLVED_QUALIFIER)
          elsif (state = line.match(STATE))
            current.state ||= state[:state].downcase
          end
        end

        # A `### F-n` block with no severity states no finding; it is prose.
        findings.reject { |finding| finding.severity.nil? }
      end

      def parse_json(path)
        JSON.parse(File.read(path)).fetch("findings", []).map do |finding|
          Finding.new(
            id: finding["id"], severity: finding["severity"].to_s.downcase,
            title: finding["title"], state: finding["status"].to_s.downcase, file: path
          )
        end
      rescue JSON::ParserError => error
        # An unreadable review is not an empty one.
        [ Finding.new(id: "(unparseable)", severity: "critical", state: "open", file: path,
          title: "the review file could not be read: #{error.message.lines.first.to_s.strip}") ]
      end
    end
  end
end
