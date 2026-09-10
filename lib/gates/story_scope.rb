# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "test_evidence"
require_relative "related_specs"
require_relative "suite_types"

module Opanel
  module Gates
    module StoryScope
      module_function

      def active_story(root)
        id = ENV["OPANEL_GATE_STORY"].to_s
        id = ENV["OPANEL_STORY"].to_s if id.empty?
        return id unless id.empty?

        marker = File.join(root, ".backlog-active")
        return nil unless File.file?(marker)

        directory = File.expand_path(File.read(marker).lines.first.to_s.strip, root)
        tasks = JSON.parse(File.read(File.join(directory, "tasks.json")))
        tasks.fetch("stories").find { |story|
 %w[in_progress review fix_required].include?(story["status"]) }&.fetch("id")
      end

      def path(root, story)
        raise ArgumentError, "invalid Story id" unless story.to_s.match?(/\AM\d{2}-\d{2}\z/)

        File.join(root, "tmp/gate/story-bases", "#{story}.json")
      end

      def start(root, story)
        target = path(root, story)
        return JSON.parse(File.read(target)).fetch("base") if File.file?(target)

        base = TestEvidence.git(root, "rev-parse", "HEAD").strip
        TestEvidence.write(target, { "story" => story, "base" => base })
        base
      end

      def base(root, story = active_story(root))
        explicit = ENV["OPANEL_GATE_BASE"].to_s
        return TestEvidence.git(root, "merge-base", "HEAD", explicit).strip unless explicit.empty?

        if !ENV["CI"] && story && File.file?(path(root, story))
          revision = JSON.parse(File.read(path(root, story))).fetch("base")
          ancestor = TestEvidence.git(root, "merge-base", "HEAD", revision).strip
          raise ArgumentError, "Story base is no longer an ancestor of HEAD" unless ancestor == revision

          return revision
        end
        TestEvidence.git(root, "merge-base", "HEAD", "main").strip
      rescue RuntimeError
        # A freshly initialized fixture may have no main. A saved or explicit
        # base must never silently fall back to a smaller scope.
        raise unless explicit.to_s.empty? && !(story && File.file?(path(root, story)))

        TestEvidence.git(root, "rev-parse", "HEAD").strip
      end

      def files(root, story = active_story(root))
        (TestEvidence.git(root, "diff", "--name-only", "--diff-filter=ACMRD", "-z", base(root, story)).split("\0") +
          TestEvidence.git(root, "ls-files", "--others", "--exclude-standard", "-z").split("\0")).uniq.sort
      end

      def required_types(root, story)
        return [] unless story

        file = Dir.glob(File.join(root, "docs/implementation", story.split("-").first, "stories",
"#{story}-*.md")).first
        return [] unless file

        section = File.read(file)[/^##\s+Required Tests\s*$(.*?)(?=^##\s|\z)/m, 1].to_s
        SuiteTypes.names.select { |type| section.match?(/\b#{Regexp.escape(type)}\b/i) }
      end

      def specs(root, story = active_story(root))
        selection = RelatedSpecs.for_changed(files(root, story), root: root)
        raise ArgumentError, "no spec is related to #{selection.uncovered.join(', ')}" unless selection.uncovered.empty?

        paths = selection.paths
        # A declared class with no mapped related spec still needs evidence;
        # conservatively run that class rather than silently dropping it.
        required_types(root, story).each do |type|
          directories = SuiteTypes.paths_for(type)
          unless paths.any? { |path| directories.any? { |dir| path == dir || path.start_with?("#{dir}/") } }
            paths += directories.select { |dir| File.directory?(File.join(root, dir)) }
          end
        end
        TestEvidence.expand(paths, root).select { |path| File.file?(File.join(root, path)) }
      end
    end
  end
end
