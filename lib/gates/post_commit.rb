# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "acceptance_mapping"
require_relative "review_findings"
require_relative "story_boundary"
require_relative "suite_types"

module Opanel
  module Gates
    # The Post-commit Gate's checks (Annex I §14.2), each a command with an exit
    # code and a reason.
    #
    # Runnable one at a time so `bin/gate` can report them individually:
    #
    #   ruby lib/gates/post_commit.rb diff-review --story M00-12
    #
    # None of them is satisfied by the agent saying so. The Autonomous Loop would
    # assert every one of them (Annex H §4.1), which is why each reads a file, a
    # commit or an exit code instead.
    module PostCommit
      CHECKS = %w[
        diff-review acceptance-mapping reviewer-findings fitness tests state pre-commit-executed
      ].freeze

      # Named by stable path, so a red check says what to write rather than only
      # that something is missing (M00-18 AC9).
      STORY_REPORT_TEMPLATE = "docs/templates/STORY_REPORT.md"
      REVIEW_FINDINGS_TEMPLATE = "docs/templates/REVIEW_FINDINGS.md"

      # Where the pre-commit hook records that it ran, keyed by the tree it saw.
      # The tree is what makes it evidence rather than a flag: `--no-verify`
      # produces a commit whose tree no hook ever recorded.
      EVIDENCE_DIRECTORY = "tmp/gate"

      # The eight items of Annex I §12.1, by the names `bin/gate pre-commit`
      # records. Declared here so a record that is missing one is a failure
      # rather than a shorter list nobody compared against anything.
      PRE_COMMIT_CHECKS = %w[
        format lint typecheck tests secret-scan migrations no-stray-files diff-boundary
      ].freeze

      Outcome = Struct.new(:ok, :reason, keyword_init: true) do
        def ok? = ok
      end

      module_function

      def ok = Outcome.new(ok: true)
      def failed(reason) = Outcome.new(ok: false, reason: reason)

      def sh(*command, root:)
        stdout, stderr, status = Open3.capture3(*command, chdir: root)
        [ stdout.strip, stderr.strip, status.success? ]
      end

      def run(check, story:, root: Dir.pwd)
        case check
        when "diff-review" then diff_review(story, root)
        when "acceptance-mapping" then acceptance_mapping(story, root)
        when "reviewer-findings" then reviewer_findings(story, root)
        when "fitness" then fitness(root)
        when "tests" then tests(story, root)
        when "state" then state(story, root)
        when "pre-commit-executed" then pre_commit_executed(root)
        else failed("unknown check: #{check} (expected #{CHECKS.join(', ')})")
        end
      end

      # "Mudanças correspondem à Story; sem surpresa." The reviewable part of
      # that is mechanical: the commit stays inside the declared boundary.
      def diff_review(story, root)
        stdout, _stderr, changed = sh("git", "show", "--name-only", "--format=", "HEAD", root: root)
        return failed("could not read the commit") unless changed

        result = StoryBoundary.check(story, stdout.split("\n").reject(&:empty?), root)
        return ok if result.status == :pass
        return ok if result.status == :skip

        failed(result.reason)
      end

      # Each acceptance criterion points at implementation, test or evidence.
      # The Story report is where that mapping lives (Annex G §22).
      #
      # Coverage, not vocabulary. The previous version passed any report
      # containing the word "acceptance", which a report mapping three of nine
      # criteria does.
      def acceptance_mapping(story, root)
        return ok if story.nil? || story.empty?

        milestone = StoryBoundary.milestone_of(story)
        report = AcceptanceMapping.report_path(root, milestone, story)
        story_file = AcceptanceMapping.story_path(root, milestone, story)

        unless File.exist?(report)
          return failed("no report at #{report.sub("#{root}/", '')} — a Story without one has no " \
                        "record of which criterion is satisfied by what. " \
                        "Template: #{STORY_REPORT_TEMPLATE}")
        end

        return failed("no Story file for #{story} in #{milestone}/stories/") if story_file.nil?

        declared = AcceptanceMapping.declared(story_file)
        if declared.empty?
          return failed("#{story} declares no acceptance criteria — a Story nobody can fail is a " \
                        "Story nobody can finish")
        end

        unmapped = AcceptanceMapping.unmapped(story_file, report)
        unless unmapped.empty?
          return failed("#{report.sub("#{root}/", '')} maps #{declared.length - unmapped.length} of " \
                        "#{declared.length} acceptance criteria; #{unmapped.join(', ')} " \
                        "#{unmapped.one? ? 'is' : 'are'} missing. Template: #{STORY_REPORT_TEMPLATE}")
        end

        unaccounted = AcceptanceMapping.unaccounted(story_file, report)
        return ok if unaccounted.empty?

        failed("criteri#{unaccounted.one? ? 'on' : 'a'} #{unaccounted.join(', ')} of #{story} " \
               "#{unaccounted.one? ? 'is' : 'are'} neither satisfied nor deferred to a named ADR or " \
               "Story. Tick the box with its evidence, or say which decision it waits on.")
      end

      # Critical = 0 and High = 0 block DONE and block merge.
      #
      # Read from the Story's own review, in the canonical Markdown form. The
      # previous version globbed `review/*.json`, of which there are none — so
      # every Story reported zero blocking findings, and a Story with no review
      # at all reported the same thing.
      def reviewer_findings(story, root)
        return ok if story.nil? || story.empty?

        directory = File.join(root, "docs/implementation", StoryBoundary.milestone_of(story), "review")

        if ReviewFindings.missing?(directory, story)
          return failed("no implementation self-review for #{story} at " \
                        "#{directory.sub("#{root}/", '')}/#{story}.md — the diff was reviewed by " \
                        "nobody, and an absent review is not a clean one. " \
                        "Template: #{REVIEW_FINDINGS_TEMPLATE}")
        end

        blocking = ReviewFindings.blocking(directory, story)
        return ok if blocking.empty?

        failed("Critical and High must be 0 before DONE: " \
               "#{blocking.map { |finding| "#{story} #{finding}" }.join('; ')}. " \
               "Severities and their blocking policy: #{REVIEW_FINDINGS_TEMPLATE}")
      end

      def fitness(root)
        _stdout, stderr, passed = sh("bin/fitness", root: root)
        passed ? ok : failed("the fitness functions are red: #{stderr.lines.first&.strip}")
      end

      # The Story's suite, green — read from the evidence bin/test writes, not
      # from a claim that it was run.
      #
      # Three things this used to accept and should not have: a run that executed
      # no examples, a run whose reports recorded failures, and one suite type
      # standing in for a Story that declares several. All three read as "pass"
      # in a file whose only checked field was `result`.
      def tests(story, root)
        evidence = File.join(root, "tmp/test-results/rspec-metadata.json")
        unless File.exist?(evidence)
          return failed("no test evidence at tmp/test-results/rspec-metadata.json — run bin/test; " \
                        "a suite nobody ran is not a suite that passed")
        end

        metadata = JSON.parse(File.read(evidence))
        return failed("the last recorded run was #{metadata['result']}") unless metadata["result"] == "pass"

        commit = metadata["commit"].to_s
        head, _stderr, _ok = sh("git", "rev-parse", "HEAD", root: root)
        unless commit.empty? || head.start_with?(commit) || commit.start_with?(head)
          return failed("the test evidence is from commit #{commit[0, 9]}, not from HEAD " \
                        "#{head[0, 9]} — re-run the suite against what was committed")
        end

        executed = metadata["tests"].to_i
        if executed.zero?
          return failed("the recorded run executed no examples. An empty run reports `pass` for the " \
                        "same reason a green suite does, and means nothing — re-run bin/test and " \
                        "check that tmp/test-results/ holds a JUnit report")
        end

        broken = metadata["failures"].to_i + metadata["errors"].to_i
        unless broken.zero?
          return failed("the recorded run has #{broken} failing example(s) despite reporting `pass`; " \
                        "the evidence contradicts itself")
        end

        uncovered = required_suites(story, root) - covered_suites(metadata)
        return ok if uncovered.empty?

        failed("the evidence is from a `#{metadata['type']}` run, which does not cover the " \
               "#{uncovered.join(', ')} suite(s) #{story} declares under Required Tests. " \
               "Run `bin/test` — evidence from a narrower run is evidence about something else.")
      end

      # What the Story declared it needs, read from its own Required Tests
      # section. Nothing here is satisfied by the agent saying the suite ran.
      def required_suites(story, root)
        return [] if story.nil? || story.empty?

        path = Dir.glob(File.join(root, "docs/implementation", StoryBoundary.milestone_of(story),
          "stories", "#{story}-*.md")).first
        return [] if path.nil?

        section = File.read(path)[/^##\s+Required Tests\s*$(.*?)(?=^##\s|\z)/m, 1].to_s
        SuiteTypes.names.select { |type| section.match?(/\b#{Regexp.escape(type)}\b/i) }
      end

      def covered_suites(metadata)
        metadata["type"].to_s == "all" ? SuiteTypes.names : [ metadata["type"].to_s ]
      end

      # tasks.json, the Story report and the commit hash agree.
      def state(story, root)
        return ok if story.nil? || story.empty?

        milestone = StoryBoundary.milestone_of(story)
        path = File.join(root, "docs/implementation", milestone, "tasks.json")
        return failed("no tasks.json for #{milestone}") unless File.exist?(path)

        entry = JSON.parse(File.read(path)).fetch("stories", []).find { |s| s["id"] == story }
        return failed("#{story} is not in #{milestone}/tasks.json") if entry.nil?

        unless entry["status"] == "done"
          return failed("#{story} is `#{entry['status']}` in tasks.json, so this commit does not " \
                        "close it — mark it done, or do not treat the Story as finished")
        end

        commit = entry["commit"].to_s
        return failed("#{story} is done with no commit hash") if commit.empty?

        _stdout, _stderr, exists = sh("git", "cat-file", "-e", "#{commit}^{commit}", root: root)
        return failed("#{story} names commit #{commit}, which is not in this repository") unless exists

        ok
      end

      # `--no-verify` leaves no trace in the commit itself. What it does leave is
      # the absence of one: the hook records the tree it checked, and a commit
      # whose tree was never recorded did not pass the gate.
      #
      # The record is read, not merely counted. A file whose existence is the
      # whole assertion is a file anyone can create, and the previous version was
      # written even when the gate had just failed.
      def pre_commit_executed(root)
        tree, _stderr, read = sh("git", "rev-parse", "HEAD^{tree}", root: root)
        return failed("could not read the commit's tree") unless read

        evidence = File.join(root, EVIDENCE_DIRECTORY, "pre-commit-#{tree}.json")
        unless File.exist?(evidence)
          return failed("no record that the Pre-commit Gate ran on this commit's tree (#{tree[0, 9]}). " \
                        "Either it was bypassed with --no-verify, or the hook is not installed: " \
                        "run bin/install-hooks. A bypass needs a recorded reason and the gate has to run " \
                        "again before merge (Annex I §12.2).")
        end

        record =
          begin
            JSON.parse(File.read(evidence))
          rescue JSON::ParserError
            return failed("the pre-commit record for #{tree[0, 9]} is not readable JSON — " \
                          "re-run `bin/gate pre-commit`")
          end

        unless record["gate"] == "pre-commit" && record["tree"] == tree
          return failed("the pre-commit record for #{tree[0, 9]} describes something else " \
                        "(gate=#{record['gate'].inspect}, tree=#{record['tree'].to_s[0, 9]})")
        end

        unless record["result"] == "pass"
          return failed("the Pre-commit Gate recorded `#{record['result']}` for this tree — " \
                        "the commit was made over a gate that had already failed")
        end

        missing = PRE_COMMIT_CHECKS - Array(record["checks"])
        return ok if missing.empty?

        failed("the pre-commit record for #{tree[0, 9]} is missing #{missing.join(', ')} — " \
               "the gate that ran is not the gate Annex I §12.1 declares. Re-run " \
               "`bin/gate pre-commit`; do not edit the record.")
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  check = ARGV[0]
  story = ARGV[2] if ARGV[1] == "--story"
  root = File.expand_path("../..", __dir__)

  outcome = Opanel::Gates::PostCommit.run(check, story: story, root: root)
  warn(outcome.reason) unless outcome.ok?
  exit(outcome.ok? ? 0 : 1)
end
