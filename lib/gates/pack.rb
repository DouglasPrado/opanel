# frozen_string_literal: true

require "json"
require_relative "json_schema"

module Opanel
  module Gates
    # The Implementation Pack's state, validated and queried.
    #
    # The autonomous loop's memory is this repository, not the conversation
    # (Annex H §5). So `tasks.json` has to be trustworthy without anyone
    # remembering what it means: a Story marked done names the commit that closed
    # it, a blocked Story carries a reproducible diagnosis, and `dependsOn`
    # describes a graph that can actually be walked.
    #
    # Two passes, in this order:
    #
    #   1. **the schema**, applied — every type, pattern, enum, bound and
    #      `additionalProperties: false` in config/pack/tasks.schema.json. It used
    #      to be called the contract and then not executed: a hand-written check
    #      covered five of its rules, so a negative `attempts`, a `commit` that is
    #      not a hash, an unknown property and a `diagnosis` under the declared
    #      minimum all validated clean;
    #   2. **the semantic rules**, which no schema expresses — a `file` that
    #      exists on disk, a `dependsOn` that names a Story of this Milestone, a
    #      cycle, a `done` with no commit behind it.
    module Pack
      SCHEMA_PATH = File.expand_path("../../config/pack/tasks.schema.json", __dir__)

      STATUSES = %w[pending ready in_progress review fix_required done blocked].freeze
      QUALIFIERS = %w[
        BLOCKED_FOR_PRODUCT_DECISION
        BLOCKED_FOR_HUMAN_APPROVAL
        BLOCKED_EXTERNAL_DEPENDENCY
      ].freeze

      Violation = Struct.new(:file, :rule, :detail, :remedy, keyword_init: true)

      module_function

      def milestone_directories(root = Dir.pwd)
        Dir.glob(File.join(root, "docs/implementation/M*")).select { |path| File.directory?(path) }.sort
      end

      def tasks_paths(root = Dir.pwd)
        milestone_directories(root).map { |path| File.join(path, "tasks.json") }.select { |p| File.exist?(p) }
      end

      def load(path)
        JSON.parse(File.read(path))
      end

      # Every rule below has cost someone a session at least once in a project
      # like this one.
      def validate(path, root = Dir.pwd)
        relative = path.sub("#{root}/", "")
        violations = []

        begin
          pack = load(path)
        rescue JSON::ParserError => error
          return [ Violation.new(file: relative, rule: "PARSEABLE", detail: error.message.lines.first.strip,
            remedy: "the loop reads this file to know where it is; it cannot recover from invalid JSON") ]
        end

        schema_violations = schema_violations(pack, relative)
        structure = structure_violations(pack, relative)

        # A document whose shape is wrong cannot be walked; the rules below would
        # raise rather than report. Everything found so far comes back instead.
        return schema_violations + structure unless structure.empty?

        violations.concat(schema_violations)

        directory = File.dirname(path)
        ids = pack.fetch("stories").map { |story| story["id"] }

        pack.fetch("stories").each do |story|
          violations.concat(story_violations(story, relative, directory, ids))
        end

        violations.concat(cycle_violations(pack, relative))
        violations
      end

      def schema
        @schema ||= JSON.parse(File.read(SCHEMA_PATH))
      end

      def schema_violations(pack, relative)
        JsonSchema.validate(schema, pack).map do |error|
          Violation.new(
            file: relative, rule: "SCHEMA", detail: error.to_s,
            remedy: "config/pack/tasks.schema.json is the contract, and this is it being applied"
          )
        end
      rescue JsonSchema::UnsupportedKeyword => error
        [ Violation.new(
          file: relative, rule: "SCHEMA", detail: error.message,
          remedy: "the schema declares something nothing enforces, which is worse than not " \
                  "declaring it — implement the keyword or remove it"
        ) ]
      end

      def structure_violations(pack, relative)
        violations = []

        %w[milestone name status dependencies stories].each do |key|
          next if pack.key?(key)

          violations << Violation.new(file: relative, rule: "SCHEMA", detail: "missing `#{key}`",
            remedy: "see config/pack/tasks.schema.json")
        end
        return violations unless violations.empty?

        unless STATUSES.include?(pack["status"])
          violations << Violation.new(
            file: relative, rule: "STATE",
            detail: "milestone status `#{pack['status']}` is not one of #{STATUSES.join(', ')}",
            remedy: "use the declared vocabulary; an unknown state stops the loop from reasoning about it"
          )
        end

        unless pack["stories"].is_a?(Array) && !pack["stories"].empty?
          violations << Violation.new(file: relative, rule: "SCHEMA", detail: "`stories` must be a non-empty array",
            remedy: "a Milestone with no Stories has nothing to execute")
        end

        violations
      end

      def story_violations(story, relative, directory, ids)
        violations = []
        id = story["id"] || "(no id)"

        %w[id file status dependsOn attempts required].each do |key|
          next if story.key?(key)

          violations << Violation.new(file: relative, rule: "SCHEMA", detail: "#{id}: missing `#{key}`",
            remedy: "see config/pack/tasks.schema.json")
        end
        return violations unless violations.empty?

        unless STATUSES.include?(story["status"])
          violations << Violation.new(
            file: relative, rule: "STATE",
            detail: "#{id}: status `#{story['status']}` is not one of #{STATUSES.join(', ')}",
            remedy: "use the declared vocabulary"
          )
        end

        unless File.exist?(File.join(directory, story["file"].to_s))
          violations << Violation.new(
            file: relative, rule: "STORY_FILE",
            detail: "#{id}: `#{story['file']}` does not exist",
            remedy: "a Story the loop cannot open is a Story it cannot implement"
          )
        end

        Array(story["dependsOn"]).each do |dependency|
          next if ids.include?(dependency)

          violations << Violation.new(
            file: relative, rule: "DEPENDENCY",
            detail: "#{id}: dependsOn `#{dependency}`, which is not a Story of this Milestone",
            remedy: "cross-Milestone order is expressed by the Milestone's own `dependencies`"
          )
        end

        # The rule that keeps `done` meaning something.
        if story["status"] == "done" && story["commit"].to_s.empty?
          violations << Violation.new(
            file: relative, rule: "DONE_HAS_COMMIT",
            detail: "#{id}: done with no commit",
            remedy: "a Story marked done with no checkpoint behind it is a claim, not a state"
          )
        end

        if story["status"] == "blocked"
          violations.concat(blocked_violations(story, relative, id))
        end

        violations
      end

      def blocked_violations(story, relative, id)
        reason = story["blockedReason"]

        if reason.nil?
          return [ Violation.new(
            file: relative, rule: "BLOCKED_HAS_REASON", detail: "#{id}: blocked with no blockedReason",
            remedy: "record the qualifier and a reproducible diagnosis — a block nobody can reproduce " \
                    "is a block nobody can clear"
          ) ]
        end

        violations = []

        unless QUALIFIERS.include?(reason["qualifier"])
          violations << Violation.new(
            file: relative, rule: "BLOCKED_HAS_REASON",
            detail: "#{id}: qualifier `#{reason['qualifier']}` is not one of #{QUALIFIERS.join(', ')}",
            remedy: "the qualifier says who can unblock it"
          )
        end

        if reason["diagnosis"].to_s.length < 20
          violations << Violation.new(
            file: relative, rule: "BLOCKED_HAS_REASON", detail: "#{id}: diagnosis is too short to be useful",
            remedy: "\"it did not work\" tells the next session nothing"
          )
        end

        violations
      end

      # A cycle is not a style problem: `bin/pack next` would never return, and
      # neither would the loop.
      def cycle_violations(pack, relative)
        graph = pack.fetch("stories").to_h { |story| [ story["id"], Array(story["dependsOn"]) ] }
        visiting = {}
        done = {}
        cycles = []

        walk = lambda do |id, trail|
          return if done[id]

          if visiting[id]
            cycles << (trail + [ id ]).join(" -> ")
            return
          end

          visiting[id] = true
          graph.fetch(id, []).each { |dependency| walk.call(dependency, trail + [ id ]) if graph.key?(dependency) }
          visiting[id] = false
          done[id] = true
        end

        graph.each_key { |id| walk.call(id, []) }

        cycles.uniq.map do |cycle|
          Violation.new(file: relative, rule: "NO_CYCLE", detail: "dependency cycle: #{cycle}",
            remedy: "`bin/pack next` would never return, and neither would the loop")
        end
      end

      # The next Story the loop may pick up: not done, not blocked, and with
      # every dependency done. Rebuilding this from the repository is what makes
      # a lost session recoverable (Annex H §16).
      def next_story(milestone, root = Dir.pwd)
        path = File.join(root, "docs/implementation", milestone, "tasks.json")
        return nil unless File.exist?(path)

        pack = load(path)
        stories = pack.fetch("stories")
        by_status = stories.to_h { |story| [ story["id"], story["status"] ] }

        # Something already underway comes first: finish it before starting more.
        underway = stories.find { |story| %w[in_progress fix_required review].include?(story["status"]) }
        return underway if underway

        stories.find do |story|
          next false unless %w[pending ready].include?(story["status"])

          Array(story["dependsOn"]).all? { |dependency| by_status[dependency] == "done" }
        end
      end
    end
  end
end
