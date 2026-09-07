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

      # Where a justification may live. A Story Report is the place Annex I §10.1
      # names; an ADR is where a stack-level choice goes instead.
      def justifications(root)
        Dir.glob([
          File.join(root, "docs/implementation/*/reports/*.md"),
          File.join(root, "docs/decisions/*.md")
        ]).map { |path| File.read(path) }.join("\n")
      end

      def check(root: Dir.pwd, base: nil)
        ref = base_ref(root, base)
        corpus = justifications(root)

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

        unless corpus.include?(name)
          violations << Violation.new(
            manifest: manifest, name: name,
            message: "`#{name}` was added and no Story Report or ADR justifies it",
            remedy: "record the problem it solves, the alternatives evaluated, its maintenance, " \
                    "security and licence posture, and the long-term impact, in the Story Report " \
                    "that adds it. Template: #{TEMPLATE}"
          )
        end

        unless lockfile.include?(name)
          violations << Violation.new(
            manifest: manifest, name: name,
            message: "`#{name}` is declared but does not appear in #{lockfile_name}",
            remedy: "an unpinned dependency resolves to a different version on every machine; " \
                    "install it and commit the lockfile"
          )
        end

        violations
      end
    end
  end
end
