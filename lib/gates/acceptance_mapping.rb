# frozen_string_literal: true

require "json"

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
    # A third rule, and it is the one the previous version was missing: the
    # evidence has to **point at something that exists**. A ticked box and a
    # non-empty cell are things the author writes about their own work, and the
    # Autonomous Loop writes them for every criterion. So a claim is accepted only
    # when it names a file in this repository or a test in this repository's
    # suites, and a deferral only when the ADR or Story it names is real.
    module AcceptanceMapping
      Criterion = Struct.new(:number, :ticked, :evidence, :deferred_to, keyword_init: true) do
        def satisfied?(verifier) = ticked && verifier.verifiable?(evidence.to_s)

        def deferred?(verifier) = verifier.resolves_reference?(deferred_to.to_s)

        def accounted?(verifier) = satisfied?(verifier) || deferred?(verifier)

        def problem(verifier)
          return nil if accounted?(verifier)
          return "#{number} (evidence points at nothing that exists)" if ticked

          "#{number}"
        end
      end

      SECTION = /^##\s+Acceptance Criteria\s*$(.*?)(?=^##\s|\z)/m
      DECLARED = /^\s*(\d+)\.\s+\S/
      CHECKLIST = /^\s*[-*]\s*\[(?<box>[ xX])\]\s*(?<number>\d+)\.\s*(?<body>.*)$/
      TABLE_ROW = /^\s*\|\s*(?<number>\d+)\s*\|(?<cells>.*)\|\s*$/
      REFERENCE = /\b(M\d{2}-\d{2}|ADR-\d{4})\b/

      # Only what is set apart as a reference counts. Prose describing the work is
      # the claim, not the evidence for it.
      QUOTED = /`([^`\n]+)`/

      # Decides whether a reference resolves, against one repository. Built once
      # per check: the spec corpus is read from disk and a criterion-by-criterion
      # grep would read it again for every claim in every report.
      class Verifier
        def initialize(root)
          @root = root
        end

        # A path in this repository, or something named in its code: a test's
        # description, a constant, a check name, a command.
        def verifiable?(text)
          text.scan(QUOTED).flatten.any? { |token| path?(token) || named_in_code?(token) }
        end

        # `spec/gates/pack_spec.rb`, `bin/fitness --format json`, `app/x.rb:42`.
        def path?(token)
          token.scan(%r{(?:\A|[\s(])([\w.\-]+(?:/[\w.\-]+)+)}).flatten.any? do |candidate|
            File.exist?(File.join(@root, candidate.split(/[:#]/).first.to_s))
          end
        end

        # A test's description, a constant, a check name — anything the report
        # quotes that the code actually contains. Checkable without running
        # anything: either the sources hold that string or they do not.
        #
        # Documentation is deliberately not in the corpus. A report justified by
        # another document is still the author writing about their own work.
        def named_in_code?(token)
          needle = token.strip.delete_prefix('"').delete_suffix('"')
          return false if needle.length < 6 || !needle.match?(/[A-Za-z]{3}/)

          corpus.include?(needle.dup.force_encoding("BINARY"))
        end

        # An ADR or a Story that exists. `ADR-0007` in a report is a deferral only
        # if somebody wrote ADR-0007.
        def resolves_reference?(text)
          reference = text[REFERENCE, 1]
          return false if reference.nil?

          if reference.start_with?("ADR-")
            !Dir.glob(File.join(@root, "docs/decisions", "#{reference.downcase}*")).empty?
          else
            packs.include?(reference)
          end
        end

        private

        CORPUS = %w[
          spec/**/*.rb e2e/**/*.ts
          app/**/*.rb app/**/*.ts app/**/*.tsx app/**/*.erb
          lib/**/*.rb bin/* config/**/*.rb config/**/*.yml db/**/*.rb
          .github/**/*.yml package.json
        ].freeze

        def corpus
          @corpus ||= CORPUS.flat_map { |glob| Dir.glob(File.join(@root, glob)) }
            .select { |path| File.file?(path) }
            .map { |path| File.read(path, encoding: "BINARY") }
            .join("\n")
            .force_encoding("BINARY")
        end

        def packs
          @packs ||= Dir.glob(File.join(@root, "docs/implementation/*/tasks.json")).flat_map do |path|
            JSON.parse(File.read(path)).fetch("stories", []).map { |story| story["id"] }
          rescue JSON::ParserError
            []
          end
        end
      end

      module_function

      def verifier(root) = Verifier.new(root)

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
            evidence = cells.drop(1).join(" ")
            current = Criterion.new(
              number: row[:number].to_i,
              ticked: cells.length >= 2 && !cells.last.empty? && cells.last != "-",
              evidence: evidence,
              deferred_to: evidence[REFERENCE, 0]
            )
          elsif (item = line.match(CHECKLIST))
            current = Criterion.new(
              number: item[:number].to_i,
              ticked: item[:box].casecmp?("x"),
              evidence: item[:body],
              deferred_to: item[:body][REFERENCE, 0]
            )
          elsif current
            # Evidence and a deferral's reason both usually wrap onto the
            # following lines. Kept until the next criterion starts.
            current.evidence = "#{current.evidence}\n#{line}"
            current.deferred_to ||= line[REFERENCE, 0]
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

      # Criteria the report mentions but neither satisfies with evidence that
      # exists nor defers to a decision that exists.
      def unaccounted(story_path, report_path, root = Dir.pwd)
        found = reported(report_path)
        check = verifier(root)

        declared(story_path).filter_map do |number|
          criterion = found[number]
          criterion&.problem(check)
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
