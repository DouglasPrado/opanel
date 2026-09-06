# frozen_string_literal: true

require "yaml"

module Opanel
  module Gates
    # Reads config/ci/jobs.yml — the pipeline definition.
    #
    # Kept in Ruby rather than inlined into the workflow YAML so that the local
    # runner, the Merge Gate and the specs all ask the same file what a job is.
    # A pipeline whose definition exists only inside a CI provider can only be
    # tested by pushing, which means it is not tested.
    module CiPipeline
      STAGES = %w[pr merge nightly rc].freeze

      Job = Struct.new(:name, :stage, :description, :commands, :populated_by,
        keyword_init: true) do
        # A slot with no commands. It reports `empty`, never `pass`: a job that
        # says green while running nothing is a false statement about the build.
        def empty? = commands.empty?
      end

      module_function

      def config(root = Dir.pwd)
        YAML.safe_load_file(File.join(root, "config/ci/jobs.yml"))
      end

      def jobs(root = Dir.pwd)
        config(root).fetch("jobs").map do |name, definition|
          Job.new(
            name: name,
            stage: definition.fetch("stage"),
            description: definition.fetch("description"),
            commands: definition.fetch("commands", []).map { |label, command| [ label, command ] },
            populated_by: definition["populated_by"]
          )
        end
      end

      def job(name, root = Dir.pwd)
        jobs(root).find { |candidate| candidate.name == name }
      end

      def names(root = Dir.pwd) = jobs(root).map(&:name)

      def for_stage(stage, root = Dir.pwd)
        jobs(root).select { |candidate| candidate.stage == stage }
      end

      # `merge` runs everything a PR runs and adds to it — the cadence of Annex
      # D §20 is cumulative, not a different pipeline.
      def stage_jobs(stage, root = Dir.pwd)
        case stage
        when "pr" then for_stage("pr", root)
        when "merge" then for_stage("pr", root) + for_stage("merge", root)
        when "nightly" then for_stage("nightly", root)
        when "rc" then for_stage("rc", root)
        else raise ArgumentError, "unknown stage: #{stage} (expected #{STAGES.join(', ')})"
        end
      end

      def required_for_merge(root = Dir.pwd)
        config(root).fetch("required_for_merge")
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  stage = ARGV[0]
  puts Opanel::Gates::CiPipeline.stage_jobs(stage).map(&:name)
end
