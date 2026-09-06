# frozen_string_literal: true

require "json"
require "open3"
require_relative "pack"

module Opanel
  module Gates
    # The Stop Gate — Annex H §4.2.
    #
    # The last word on "may the loop stop". `/goal`'s evaluator has no tools and
    # can only judge whether a *declared* condition looks demonstrated; this
    # decides whether it actually is, by running commands and reading exit codes
    # (Annex H §4.1).
    #
    # **No check here is satisfiable by the agent saying so.** That is the whole
    # design: an agent asked whether its work is finished will say yes, and the
    # failure mode of the loop is not malice but optimism. Every check below
    # executes something and reports what it got.
    #
    # A red gate is not an error — it is the loop being told to keep working, with
    # a reason specific enough to act on.
    module StopGate
      Check = Struct.new(:name, :result, :duration_ms, :reason, keyword_init: true) do
        def passed? = result == "pass"
      end

      # Named by stable path, so a red check says what to write rather than only
      # that something is missing (M00-18 AC9).
      TEMPLATES = {
        story_report: "docs/templates/STORY_REPORT.md",
        milestone_report: "docs/templates/MILESTONE_REPORT.md",
        review_findings: "docs/templates/REVIEW_FINDINGS.md",
        blocker: "docs/templates/BLOCKER.md"
      }.freeze

      # Ordered cheapest-first, so a run that is going to fail usually fails in
      # seconds rather than after the whole suite.
      CHECKS = %w[
        workspace-clean
        pack-consistent
        static
        security
        unit
        integration
        contract
        acceptance
        findings
        milestone-report
      ].freeze

      class Runner
        def initialize(milestone:, root: Dir.pwd, only: nil)
          @milestone = milestone
          @root = root
          @only = only
          @checks = []
        end

        attr_reader :checks

        def run
          (@only || CHECKS).each { |name| perform(name) }
          self
        end

        def ok? = checks.all?(&:passed?)

        # The first failure, which is the one the loop should act on.
        def reason
          return nil if ok?

          failed = checks.reject(&:passed?)
          failed.map { |check| "#{check.name}: #{check.reason}" }.join("; ")
        end

        def to_h
          { ok: ok?, milestone: @milestone, reason: reason, checks: checks.map(&:to_h) }
        end

        private

        def perform(name)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          reason = send(name.tr("-", "_"))
          @checks << Check.new(
            name: name, result: reason.nil? ? "pass" : "fail",
            duration_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started,
            reason: reason
          )
        rescue StandardError => error
          @checks << Check.new(name: name, result: "fail", duration_ms: 0,
            reason: "the check itself failed: #{error.class}: #{error.message}")
        end

        def sh(*command)
          stdout, stderr, status = Open3.capture3(*command, chdir: @root)
          [ stdout, stderr, status.success? ]
        end

        def job(name)
          _stdout, _stderr, passed = sh("bin/ci-job", name)
          return nil if passed

          "`bin/ci-job #{name}` is red — run it to see which check failed"
        end

        def milestone_directory = File.join(@root, "docs/implementation", @milestone)

        # --- the checks -------------------------------------------------------

        # No production credential may exist in the workspace at all (Annex H
        # §3.2). First, because everything after it runs against that workspace.
        def workspace_clean
          _stdout, stderr, clean = sh("bin/workspace-guardrail")
          return nil if clean

          "the workspace guardrail found something: #{stderr.lines.first&.strip}"
        end

        def pack_consistent
          _stdout, _stderr, valid = sh("bin/pack", "validate", @milestone)
          return nil if valid

          "`bin/pack validate #{@milestone}` is red — run it for the violations"
        end

        def static = job("static")
        def security = job("security-fast")
        def unit = job("unit")
        def integration = job("integration")
        def contract = job("contract")

        # Annex H §4.2's "story acceptance script". There is no per-Story script
        # in this repository, and inventing one that the agent writes would be a
        # check the agent grades. What is verifiable is that every required Story
        # is done and has a report that maps its acceptance criteria to something.
        def acceptance
          path = File.join(milestone_directory, "tasks.json")
          return "no tasks.json for #{@milestone}" unless File.exist?(path)

          stories = Pack.load(path).fetch("stories")
          required = stories.select { |story| story["required"] }

          unfinished = required.reject { |story| story["status"] == "done" }
          unless unfinished.empty?
            return "required Stories are not done: " +
                   unfinished.map { |s| "#{s['id']} (#{s['status']})" }.join(", ") +
                   ". A Story that cannot be finished is blocked, with a qualifier and a " \
                   "reproducible diagnosis: #{TEMPLATES[:blocker]}"
          end

          missing = required.reject do |story|
            report = File.join(milestone_directory, "reports", "#{story['id']}.md")
            File.exist?(report) && File.read(report).match?(/acceptance/i)
          end
          return nil if missing.empty?

          "no acceptance mapping for #{missing.map { |s| s['id'] }.join(', ')} — " \
            "a criterion that points at nothing is not satisfied. " \
            "Template: #{TEMPLATES[:story_report]}"
        end

        # Critical = 0 and High = 0 block DONE and block merge.
        def findings
          blocking = []

          Dir.glob(File.join(milestone_directory, "review", "*.json")).each do |path|
            JSON.parse(File.read(path)).fetch("findings", []).each do |finding|
              severity = finding["severity"].to_s.downcase
              next unless %w[critical high].include?(severity)
              next if finding["status"].to_s == "resolved"

              blocking << "#{File.basename(path, '.json')}: #{severity}"
            end
          end

          return nil if blocking.empty?

          "Critical and High must be 0: #{blocking.join(', ')}. " \
            "Severities and their blocking policy: #{TEMPLATES[:review_findings]}"
        end

        def milestone_report
          path = File.join(milestone_directory, "MILESTONE_REPORT.md")
          unless File.exist?(path)
            return "no MILESTONE_REPORT.md for #{@milestone} — the Milestone has produced no account " \
                   "of itself, and the next session has nothing to read. " \
                   "Template: #{TEMPLATES[:milestone_report]}"
          end

          contents = File.read(path)
          return nil if contents.match?(/^Status:\s*\S+/)

          "MILESTONE_REPORT.md declares no Status: — see #{TEMPLATES[:milestone_report]}"
        end
      end
    end
  end
end
