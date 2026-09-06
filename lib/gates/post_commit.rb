# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "story_boundary"

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

      # Where the pre-commit hook records that it ran, keyed by the tree it saw.
      # The tree is what makes it evidence rather than a flag: `--no-verify`
      # produces a commit whose tree no hook ever recorded.
      EVIDENCE_DIRECTORY = "tmp/gate"

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
        when "tests" then tests(root)
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
      def acceptance_mapping(story, root)
        return ok if story.nil? || story.empty?

        report = File.join(root, "docs/implementation", StoryBoundary.milestone_of(story),
          "reports", "#{story}.md")
        unless File.exist?(report)
          return failed("no report at #{report.sub("#{root}/", '')} — a Story without one has no " \
                        "record of which criterion is satisfied by what")
        end

        contents = File.read(report)
        unless contents.match?(/acceptance/i)
          return failed("#{report.sub("#{root}/", '')} maps no acceptance criteria")
        end

        ok
      end

      # Critical = 0 and High = 0 block DONE and block merge.
      def reviewer_findings(story, root)
        return ok if story.nil? || story.empty?

        milestone = StoryBoundary.milestone_of(story)
        blocking = []

        Dir.glob(File.join(root, "docs/implementation", milestone, "review", "*.json")).each do |path|
          JSON.parse(File.read(path)).fetch("findings", []).each do |finding|
            severity = finding["severity"].to_s.downcase
            next unless %w[critical high].include?(severity)
            next if finding["status"].to_s == "resolved"

            blocking << "#{File.basename(path)}: #{severity} — #{finding['title']}"
          end
        end

        return ok if blocking.empty?

        failed("Critical and High must be 0 before DONE: #{blocking.join('; ')}")
      end

      def fitness(root)
        _stdout, stderr, passed = sh("bin/fitness", root: root)
        passed ? ok : failed("the fitness functions are red: #{stderr.lines.first&.strip}")
      end

      # The Story's suite, green — read from the evidence bin/test writes, not
      # from a claim that it was run.
      def tests(root)
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

        ok
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
      def pre_commit_executed(root)
        tree, _stderr, read = sh("git", "rev-parse", "HEAD^{tree}", root: root)
        return failed("could not read the commit's tree") unless read

        evidence = File.join(root, EVIDENCE_DIRECTORY, "pre-commit-#{tree}.json")
        return ok if File.exist?(evidence)

        failed("no record that the Pre-commit Gate ran on this commit's tree (#{tree[0, 9]}). " \
               "Either it was bypassed with --no-verify, or the hook is not installed: " \
               "run bin/install-hooks. A bypass needs a recorded reason and the gate has to run " \
               "again before merge (Annex I §12.2).")
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
