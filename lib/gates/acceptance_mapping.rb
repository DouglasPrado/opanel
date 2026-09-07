# frozen_string_literal: true

module Opanel
  module Gates
    # Every acceptance criterion of a Story, against what its report says about it.
    #
    # The gates used to accept any report containing the word "acceptance". That
    # is a check on vocabulary, not on work: a report mapping three of nine
    # criteria passed, and so did one that mentioned the section and filled in
    # nothing. The Autonomous Loop would assert the criteria were met (Annex H
    # §4.1), which is precisely why the assertion cannot be the evidence.
    #
    # What is mechanically decidable is coverage and accounting:
    #
    #   * every criterion the Story declares appears in the report;
    #   * each one is either **satisfied** — a ticked box, or a table row with a
    #     non-empty evidence cell — or **deferred to a named decision**, an ADR or
    #     a Story id, the same rule the Suppression Gate applies to a silenced
    #     lint rule.
    #
    # An unticked box with no reference is a criterion nobody has satisfied and
    # nobody has accounted for, which is the state a Story may not close in.
    module AcceptanceMapping
      Criterion = Struct.new(:number, :satisfied, :deferred_to, keyword_init: true) do
        def accounted? = satisfied || !deferred_to.to_s.empty?
      end

      SECTION = /^##\s+Acceptance Criteria\s*$(.*?)(?=^##\s|\z)/m
      DECLARED = /^\s*(\d+)\.\s+\S/
      CHECKLIST = /^\s*[-*]\s*\[(?<box>[ xX])\]\s*(?<number>\d+)\.\s*(?<body>.*)$/
      TABLE_ROW = /^\s*\|\s*(?<number>\d+)\s*\|(?<cells>.*)\|\s*$/
      REFERENCE = /\b(M\d{2}-\d{2}|ADR-\d{4}|#\d+)\b/

      module_function

      def section(path)
        File.exist?(path) ? File.read(path)[SECTION, 1].to_s : ""
      end

      def declared(story_path)
        section(story_path).lines.filter_map { |line| line[DECLARED, 1]&.to_i }
      end

      def reported(report_path)
        criteria = {}
        current = nil

        section(report_path).each_line do |line|
          if (row = line.match(TABLE_ROW))
            cells = row[:cells].split("|").map(&:strip)
            evidence = cells.length >= 2 && !cells.last.empty? && cells.last != "-"
            current = Criterion.new(number: row[:number].to_i, satisfied: evidence)
          elsif (item = line.match(CHECKLIST))
            current = Criterion.new(
              number: item[:number].to_i,
              satisfied: item[:box].casecmp?("x"),
              deferred_to: item[:body][REFERENCE, 1]
            )
          elsif current && !current.accounted?
            # A deferral's reason usually wraps onto the following line.
            current.deferred_to = line[REFERENCE, 1]
            next
          else
            next
          end

          criteria[current.number] = current
        end

        criteria
      end

      # Criteria the report never mentions.
      def unmapped(story_path, report_path)
        declared(story_path) - reported(report_path).keys
      end

      # Criteria the report mentions but neither satisfies nor defers to a named
      # decision.
      def unaccounted(story_path, report_path)
        found = reported(report_path)

        declared(story_path).select do |number|
          criterion = found[number]
          criterion && !criterion.accounted?
        end
      end

      def story_path(root, milestone, story)
        Dir.glob(File.join(root, "docs/implementation", milestone, "stories", "#{story}-*.md")).first
      end

      def report_path(root, milestone, story)
        File.join(root, "docs/implementation", milestone, "reports", "#{story}.md")
      end
    end
  end
end
