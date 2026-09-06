# frozen_string_literal: true

require "json"
require "yaml"

module Opanel
  module Gates
    # The declared boundary of a Story, and the checks that hold a commit to it.
    #
    # "Changes outside the declared boundary are a review finding even when the
    # code is correct" (AGENT_RULES, "Scope Discipline"). That rule needs
    # something to compare against, so a Story declares the paths it may touch in
    # `docs/implementation/<milestone>/boundaries.yml` **before** editing —
    # afterwards the boundary is just a description of whatever happened.
    #
    # An undeclared boundary fails rather than passes. The alternative is a check
    # that is satisfied by never declaring anything, which is worse than not
    # having it: it reports green over exactly the scope creep it exists to catch.
    module StoryBoundary
      # Always allowed, for every Story. The pack's own bookkeeping is not scope
      # creep — a Story that could not record its own state would be unable to
      # finish.
      ALWAYS = [
        "docs/implementation/*/tasks.json",
        "docs/implementation/*/reports/*.md",
        "docs/implementation/*/review/*.md",
        "docs/implementation/*/evidence/**",
        "docs/implementation/*/boundaries.yml",
        "docs/implementation/*/MILESTONE_REPORT.md",
        "docs/implementation/*/BLOCKERS.md"
      ].freeze

      Result = Struct.new(:status, :reason, :outside, keyword_init: true) do
        def pass? = status == :pass
      end

      module_function

      def milestone_of(story) = story.to_s.split("-").first

      # `.github/**` reads as "everything under .github", but Ruby's fnmatch only
      # recurses through the `**/` form — so the bare trailing `**` matched
      # nothing below the first level and rejected files the boundary plainly
      # allowed. Expanding it here keeps the declarations readable and the
      # matching correct.
      def expand(pattern)
        pattern.end_with?("/**") ? "#{pattern}/*" : pattern
      end

      def path(story, root = Dir.pwd)
        File.join(root, "docs/implementation", milestone_of(story), "boundaries.yml")
      end

      def declared(story, root = Dir.pwd)
        file = path(story, root)
        return nil unless File.exist?(file)

        YAML.safe_load_file(file).fetch("boundaries", {})[story]
      end

      # Returns the files that fall outside the Story's declared boundary.
      def check(story, files, root = Dir.pwd)
        if story.nil? || story.empty?
          return Result.new(
            status: :skip,
            reason: "no Story declared — pass --story <id> or set OPANEL_STORY to check the boundary"
          )
        end

        globs = declared(story, root)
        if globs.nil?
          return Result.new(
            status: :fail,
            reason: "#{story} declares no boundary in #{path(story, root).sub("#{root}/", '')}. " \
                    "Declare the paths the Story may touch before editing — a boundary written " \
                    "afterwards only describes what happened."
          )
        end

        patterns = (globs + ALWAYS).map { |pattern| expand(pattern) }
        outside = files.reject do |file|
          patterns.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end

        return Result.new(status: :pass) if outside.empty?

        Result.new(
          status: :fail,
          outside: outside,
          reason: "outside the boundary of #{story}: #{outside.join(', ')}. " \
                  "Either the change belongs to another Story, or the boundary was declared too " \
                  "narrowly and should be widened deliberately."
        )
      end
    end
  end
end
