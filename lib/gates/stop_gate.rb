# frozen_string_literal: true

require "json"
require "open3"
require_relative "acceptance_mapping"
require_relative "pack"
require_relative "review_findings"

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
        # check the agent grades. What *is* verifiable is that every required
        # Story is done and that its report accounts for every criterion the
        # Story declares — by number, one at a time.
        #
        # The previous version accepted any report matching /acceptance/i, so a
        # report that mapped a third of the criteria was indistinguishable from
        # one that mapped all of them.
        def acceptance
          path = File.join(milestone_directory, "tasks.json")
          return "no tasks.json for #{@milestone}" unless File.exist?(path)

          required = Pack.load(path).fetch("stories").select { |story| story["required"] }

          unfinished = required.reject { |story| story["status"] == "done" }
          unless unfinished.empty?
            return "required Stories are not done: " +
                   unfinished.map { |s| "#{s['id']} (#{s['status']})" }.join(", ") +
                   ". A Story that cannot be finished is blocked, with a qualifier and a " \
                   "reproducible diagnosis: #{TEMPLATES[:blocker]}"
          end

          problems = required.filter_map { |story| acceptance_problem(story["id"]) }
          return nil if problems.empty?

          "#{problems.join('; ')}. A criterion that points at nothing is not satisfied. " \
            "Template: #{TEMPLATES[:story_report]}"
        end

        def acceptance_problem(story)
          report = AcceptanceMapping.report_path(@root, @milestone, story)
          return "#{story} has no report" unless File.exist?(report)

          story_file = AcceptanceMapping.story_path(@root, @milestone, story)
          return "#{story} has no Story file" if story_file.nil?

          declared = AcceptanceMapping.declared(story_file)
          return "#{story} declares no acceptance criteria" if declared.empty?

          unmapped = AcceptanceMapping.unmapped(story_file, report)
          return "#{story} maps #{declared.length - unmapped.length}/#{declared.length} criteria " \
                 "(missing #{unmapped.join(', ')})" unless unmapped.empty?

          unaccounted = AcceptanceMapping.unaccounted(story_file, report, @root)
          return nil if unaccounted.empty?

          "#{story} criteria #{unaccounted.join(', ')} are neither satisfied by evidence that " \
            "exists nor deferred to an ADR or Story that exists"
        end

        # Critical = 0 and High = 0 block DONE and block merge.
        #
        # Read from the Markdown reviews that actually exist. The glob was
        # `review/*.json`, of which there are none: eighteen reviews sat next to
        # it unread, and a Milestone with no review at all reported clean.
        def findings
          path = File.join(milestone_directory, "tasks.json")
          return "no tasks.json for #{@milestone}" unless File.exist?(path)

          directory = File.join(milestone_directory, "review")
          required = Pack.load(path).fetch("stories").select { |story| story["required"] }

          missing = required.map { |story| story["id"] }
            .select { |story| ReviewFindings.missing?(directory, story) }
          unless missing.empty?
            return "no implementation self-review for #{missing.join(', ')} — an absent review is " \
                   "not a clean one. Template: #{TEMPLATES[:review_findings]}"
          end

          blocking = required.flat_map do |story|
            ReviewFindings.blocking(directory, story["id"]).map { |finding| "#{story['id']} #{finding}" }
          end
          return nil if blocking.empty?

          "Critical and High must be 0: #{blocking.join('; ')}. " \
            "Severities and their blocking policy: #{TEMPLATES[:review_findings]}"
        end

        # The sections docs/templates/MILESTONE_REPORT.md declares, each of which
        # a human reads to decide acceptance. Named here so a report that omits
        # one fails rather than passing as a shorter document nobody compared
        # against anything.
        MILESTONE_SECTIONS = [
          "Stories", "Quality", "Findings", "Resultado funcional", "Blocked",
          "Dependências novas", "Conflitos de especificação", "Human acceptance requested"
        ].freeze

        # A report that only declared `Status:` passed this. That is the one line
        # the orchestrator needs and the one line that says nothing: the Milestone
        # can be handed on for review with no account of its Stories, its gates,
        # its findings or what a human is being asked to accept.
        def milestone_report
          path = File.join(milestone_directory, "MILESTONE_REPORT.md")
          unless File.exist?(path)
            return "no MILESTONE_REPORT.md for #{@milestone} — the Milestone has produced no account " \
                   "of itself, and the next session has nothing to read. " \
                   "Template: #{TEMPLATES[:milestone_report]}"
          end

          contents = File.read(path)
          unless contents.match?(/^Status:\s*\S+/)
            return "MILESTONE_REPORT.md declares no Status: — see #{TEMPLATES[:milestone_report]}"
          end

          missing = MILESTONE_SECTIONS.reject do |heading|
            body = contents[/^#{'#'}{2,3}\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^#{'#'}{1,3}\s|\z)/m, 1]
            body.to_s.strip.length > 3
          end
          return nil if missing.empty?

          "MILESTONE_REPORT.md has no #{missing.join(', ')} section, or leaves it empty — " \
            "see #{TEMPLATES[:milestone_report]}"
        end
      end
    end
  end
end
