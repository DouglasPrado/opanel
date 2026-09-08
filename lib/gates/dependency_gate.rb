# frozen_string_literal: true

require "json"
require "open3"

module Opanel
  module Gates
    # The Dependency Gate — Annex I §10, M00-10 AC7.
    #
    # It was documented as a checklist and never executed, and the only thing
    # standing in for it was a spec asserting that ten hard-coded names appeared
    # somewhere in the reports. A list written by hand does not notice the
    # eleventh dependency, which is the one the gate exists for.
    #
    # So: the direct dependencies of the working tree are compared with those of
    # the base, and each **added** name has to be justified in the Story Report
    # that added it or in an ADR, and pinned in the lockfile. "For convenience"
    # is not a justification, and a name nobody wrote about is exactly that.
    #
    # Only direct dependencies. A transitive one is a consequence of a decision
    # somebody already justified; making a reviewer account for four hundred of
    # them is how a gate gets ignored.
    module DependencyGate
      Violation = Struct.new(:manifest, :name, :message, :remedy, keyword_init: true) do
        def to_h = { manifest: manifest, name: name, message: message, remedy: remedy }
      end

      GEMFILE = "Gemfile"
      GEMFILE_LOCK = "Gemfile.lock"
      PACKAGE_JSON = "package.json"
      PACKAGE_LOCK = "package-lock.json"

      GEM_LINE = /^\s*gem\s+["']([^"']+)["']/

      TEMPLATE = "docs/templates/DEPENDENCY_JUSTIFICATION.md"

      module_function

      def sh(*command, root:)
        stdout, _stderr, status = Open3.capture3(*command, chdir: root)
        [ stdout, status.success? ]
      end

      # The merge base with the default branch: what this branch actually added.
      def base_ref(root, requested = nil)
        return requested unless requested.to_s.empty?

        stdout, ok = sh("git", "merge-base", "HEAD", ENV.fetch("OPANEL_GATE_BASE", "main"), root: root)
        ok ? stdout.strip : nil
      end

      def working_tree(root, path)
        full = File.join(root, path)
        File.exist?(full) ? File.read(full) : ""
      end

      def at_ref(root, ref, path)
        return "" if ref.nil? || ref.empty?

        stdout, ok = sh("git", "show", "#{ref}:#{path}", root: root)
        ok ? stdout : ""
      end

      def gems(source)
        source.to_s.lines.filter_map { |line| line[GEM_LINE, 1] }.uniq
      end

      def packages(source)
        return [] if source.to_s.strip.empty?

        document = JSON.parse(source)
        (document.fetch("dependencies", {}).keys + document.fetch("devDependencies", {}).keys).uniq
      rescue JSON::ParserError
        []
      end

      # What Annex I §10.1 requires a justification to answer, in the shape
      # docs/templates/DEPENDENCY_JUSTIFICATION.md writes it. The gate checked
      # `corpus.include?(name)` — a substring search over every report and ADR in
      # the repository. The word `redis` in a paragraph about something else
      # justified adding redis, and so did the gem's own name in an unrelated
      # dependency table.
      # What is checked instead is a **declaration in the section that exists for
      # it** — "Dependências novas" in a Story Report, or an ADR — with the
      # questions of Annex I §10.1 answered there.
      SECTION = /^#{'#'}{2,3}\s+(?:Depend[êe]ncias\s+novas|New\s+dependencies)\s*$(.*?)(?=^#{'#'}{1,2}\s|\z)/mi

      # The template's per-dependency block, answered field by field.
      BLOCK_FIELDS = {
        "the problem it solves" => /(?:Problema resolvido|Problem solved)[^:\n]*:\**\s*\S/i,
        "the alternatives" => /(?:Alternativas avaliadas|Alternatives evaluated)[^:\n]*:\**\s*\S/i,
        "its maintenance" => /Maintenance[^:\n]*:\**\s*\S/i,
        "its security posture" => /Security[^:\n]*:\**\s*\S/i,
        "its licence" => /Licen[cs]e[^:\n]*:\**\s*\S/i,
        "the lockfile it is pinned in" => /Lockfile[^:\n]*:\**\s*\S/i
      }.freeze

      # What the section as a whole has to state when a dependency is declared in
      # a table row or on its own line rather than in a full block: the two facts
      # a row has no column for.
      SECTION_FIELDS = {
        "its licence" => /\b(?:MIT|Apache|BSD|ISC|MPL|LGPL|permissive|licen[cs]ed?)\b/i,
        "the lockfile it is pinned in" => /(?:Gemfile\.lock|package-lock\.json)/
      }.freeze

      # The block header the template declares: `### Dependency: \`name\` version`.
      def justification_sections(root)
        Dir.glob([
          File.join(root, "docs/implementation/*/reports/*.md"),
          File.join(root, "docs/decisions/*.md")
        ]).flat_map { |path| File.read(path).scan(SECTION).flatten }
      end

      def block_for(name, section)
        section[/^#{'#'}{2,4}\s+Dependency:\s*`?#{Regexp.escape(name)}`?[^\n]*\n(.*?)(?=^#{'#'}{1,6}\s|\z)/m, 1]
      end

      # Where a name counts as *declared* rather than merely mentioned: the first
      # cell of a table row, or the start of its own line — optionally in a
      # comma-separated list, which is how the reports group packages that arrive
      # together. Either way it has to carry something besides the name.
      def declared_row(name, section)
        quoted = "`#{name}`"

        section.lines.map(&:strip).find do |line|
          next false unless line.include?(quoted)

          if (cells = line[/\A\|(.+)\z/, 1])
            columns = cells.split("|")
            columns.first.to_s.include?(quoted) && columns.drop(1).any? { |cell| cell.strip.length > 1 }
          else
            line.match?(/\A(?:[-*]\s*)?(?:`[^`]+`(?:\s*,\s*|\s+(?:and|e)\s+))*#{Regexp.escape(quoted)}(?:\W|\z)/) &&
              line.length > quoted.length + 2
          end
        end
      end

      # nil when nothing declares it; otherwise the questions still unanswered.
      # A heading with nothing under it is the "for convenience" this gate exists
      # to refuse.
      def justification_for(name, sections)
        sections.filter_map do |section|
          if (block = block_for(name, section))
            BLOCK_FIELDS.reject { |_field, pattern| block.match?(pattern) }.keys
          elsif declared_row(name, section)
            SECTION_FIELDS.reject { |_field, pattern| section.match?(pattern) }.keys
          end
        end.min_by(&:length)
      end

      # Declared in the lockfile, as a dependency rather than as a substring.
      # `lockfile.include?("rack")` was satisfied by `rack-test`, by a URL, and by
      # a gem that merely depends on it.
      def locked?(name, lockfile, lockfile_name)
        case lockfile_name
        when GEMFILE_LOCK
          # `    rack (3.1.8)` under specs, or a name in DEPENDENCIES.
          lockfile.match?(/^\s{4}#{Regexp.escape(name)}\s\(/) ||
            lockfile.match?(/^\s{2}#{Regexp.escape(name)}(?:\s|$)/)
        when PACKAGE_LOCK
          document = JSON.parse(lockfile)
          document.fetch("packages", {}).key?("node_modules/#{name}") ||
            document.fetch("dependencies", {}).key?(name)
        else
          false
        end
      rescue JSON::ParserError
        false
      end

      def check(root: Dir.pwd, base: nil)
        ref = base_ref(root, base)
        corpus = justification_sections(root)

        added = {
          GEMFILE => [
            gems(working_tree(root, GEMFILE)) - gems(at_ref(root, ref, GEMFILE)),
            working_tree(root, GEMFILE_LOCK), GEMFILE_LOCK
          ],
          PACKAGE_JSON => [
            packages(working_tree(root, PACKAGE_JSON)) - packages(at_ref(root, ref, PACKAGE_JSON)),
            working_tree(root, PACKAGE_LOCK), PACKAGE_LOCK
          ]
        }

        added.flat_map do |manifest, (names, lockfile, lockfile_name)|
          names.flat_map { |name| violations_for(manifest, name, corpus, lockfile, lockfile_name) }
        end
      end

      def violations_for(manifest, name, corpus, lockfile, lockfile_name)
        violations = []
        incomplete = justification_for(name, corpus)

        if incomplete.nil?
          violations << Violation.new(
            manifest: manifest, name: name,
            message: "`#{name}` was added and no Story Report or ADR justifies it",
            remedy: "record the problem it solves, the alternatives evaluated, its maintenance, " \
                    "security and licence posture, and the long-term impact, in the Story Report " \
                    "that adds it. Template: #{TEMPLATE}"
          )
        elsif !incomplete.empty?
          violations << Violation.new(
            manifest: manifest, name: name,
            message: "the justification for `#{name}` answers neither #{incomplete.join(' nor ')}",
            remedy: "a heading with nothing under it is the \"for convenience\" this gate refuses. " \
                    "Fill in every field of #{TEMPLATE}"
          )
        end

        unless locked?(name, lockfile, lockfile_name)
          violations << Violation.new(
            manifest: manifest, name: name,
            message: "`#{name}` is declared but is not pinned in #{lockfile_name}",
            remedy: "an unpinned dependency resolves to a different version on every machine; " \
                    "install it and commit the lockfile"
          )
        end

        violations
      end
    end
  end
end
