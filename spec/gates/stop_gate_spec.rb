require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/gates/stop_gate"

# The Stop Gate — the last word on "may the loop stop".
#
# The property under test is not that it passes. It is that it **cannot be
# satisfied by assertion**: an agent asked whether its work is finished will say
# yes, and the failure mode of an autonomous loop is optimism rather than malice
# (Annex H §4.1). So every check has to run something, and the gate has to keep
# saying no while the evidence is missing.
RSpec.describe Opanel::Gates::StopGate do
  STOP_GATE_ROOT = File.expand_path("../..", __dir__)

  def run_gate(*arguments, root: STOP_GATE_ROOT)
    Open3.capture2e("bin/stop-gate", *arguments, chdir: root)
  end

  # The cheap checks: enough to exercise the contract without running the whole
  # suite, which the pipeline runs anyway.
  CHEAP = "workspace-clean,pack-consistent,acceptance,findings,milestone-report"

  describe "the contract" do
    # AC3.
    it "emits ok, reason and a result per check" do
      output, _status = run_gate("M00", "--only", CHEAP)
      report = JSON.parse(output)

      expect(report).to include("ok", "reason", "checks")
      expect(report["checks"]).to all(include("name", "result", "duration_ms"))
    end

    it "covers the checklist of Annex H §4.2" do
      expect(described_class::CHECKS).to include(
        "static", "unit", "integration", "contract", "security",
        "acceptance", "pack-consistent", "findings", "milestone-report"
      )
    end

    it "orders the cheap checks first, so a doomed run fails in seconds" do
      order = described_class::CHECKS

      expect(order.index("workspace-clean")).to be < order.index("unit")
      expect(order.index("pack-consistent")).to be < order.index("integration")
    end

    it "refuses a check it does not have" do
      output, status = run_gate("M00", "--only", "vibes")

      expect(status).not_to be_success
      expect(output).to include("unknown check")
    end

    # Asked about a Milestone that does not exist, so the answer is `no` whatever
    # M00 happens to look like. An earlier version used M00's own missing
    # MILESTONE_REPORT.md and went green the moment the report was written —
    # a "must be red" case that quietly stopped being red.
    #
    # `ok:false` is the answer, not a crash: the caller reads the field.
    it "exits 0 in JSON mode even when the answer is no" do
      output, status = run_gate("M99", "--only", "acceptance")

      expect(status).to be_success
      expect(JSON.parse(output)["ok"]).to be(false)
    end

    it "exits non-zero in text mode, so a shell `&&` behaves" do
      _output, status = run_gate("M99", "--only", "acceptance", "--format", "text")

      expect(status).not_to be_success
    end
  end

  # AC4, AC9: the reason has to be usable without guessing.
  describe "a red check" do
    def check_in(report, name) = report["checks"].find { |check| check["name"] == name }

    it "names what is missing rather than reporting that something is wrong" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "docs/implementation/M99"))

        runner = described_class::Runner.new(
          milestone: "M99", root: root, only: [ "milestone-report" ]
        ).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("no MILESTONE_REPORT.md")
      end
    end

    # M00-R07. A report declaring only `Status:` passed. That is the one line the
    # orchestrator needs and the one line that says nothing: the Milestone could be
    # handed on for review with no account of its Stories, its gates, its findings,
    # or what a human is being asked to accept.
    describe "a Milestone Report that says only that it is ready" do
      def milestone_report(contents)
        Dir.mktmpdir do |root|
          directory = File.join(root, "docs/implementation/M99")
          FileUtils.mkdir_p(directory)
          File.write(File.join(directory, "MILESTONE_REPORT.md"), contents)

          yield described_class::Runner.new(
            milestone: "M99", root: root, only: [ "milestone-report" ]
          ).run
        end
      end

      let(:sections) { described_class::Runner::MILESTONE_SECTIONS }

      it "is refused, naming every section it left out" do
        milestone_report("# Milestone Report — M99\n\nStatus: READY_FOR_REVIEW\n") do |runner|
          expect(runner).not_to be_ok
          sections.each { |heading| expect(runner.reason).to include(heading) }
        end
      end

      it "is refused when a section is present but empty" do
        body = +"# Milestone Report — M99\n\nStatus: READY_FOR_REVIEW\n"
        sections.each { |heading| body << "\n## #{heading}\n\n#{heading == 'Blocked' ? '' : 'ok.'}\n" }

        milestone_report(body) do |runner|
          expect(runner).not_to be_ok
          expect(runner.reason).to include("Blocked")
        end
      end

      it "is accepted once every section says something" do
        body = +"# Milestone Report — M99\n\nStatus: READY_FOR_REVIEW\n"
        sections.each { |heading| body << "\n## #{heading}\n\n`none`.\n" }

        milestone_report(body) { |runner| expect(runner).to be_ok }
      end
    end

    it "refuses a Milestone whose required Stories are not done" do
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99")
        FileUtils.mkdir_p(directory)
        File.write(File.join(directory, "tasks.json"), JSON.generate(stories: [
          { "id" => "M99-01", "status" => "in_progress", "required" => true }
        ]))

        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "acceptance" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("M99-01 (in_progress)")
      end
    end

    # A throwaway Milestone: one required, done Story, with whatever Story file,
    # report and review the example wants beside it.
    def with_milestone(story: nil, report: nil, review: nil)
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99")
        FileUtils.mkdir_p(File.join(directory, "stories"))
        FileUtils.mkdir_p(File.join(directory, "reports"))
        FileUtils.mkdir_p(File.join(directory, "review"))

        File.write(File.join(directory, "tasks.json"), JSON.generate(stories: [
          { "id" => "M99-01", "status" => "done", "required" => true, "commit" => "a1b2c3d" }
        ]))
        File.write(File.join(directory, "stories/M99-01-probe.md"), story) if story
        File.write(File.join(directory, "reports/M99-01.md"), report) if report
        File.write(File.join(directory, "review/M99-01.md"), review) if review

        yield root
      end
    end

    def story_declaring_three
      <<~MARKDOWN
        # M99-01 — Probe

        ## Acceptance Criteria
        1. The first thing happens.
        2. The second thing happens.
        3. The third thing happens.
      MARKDOWN
    end

    # An acceptance criterion that points at nothing is not satisfied, and the
    # report is where it points. Checking that the word "acceptance" appears
    # somewhere is not checking that.
    it "refuses a done Story whose report maps no acceptance criteria" do
      with_milestone(story: story_declaring_three,
        report: "# M99-01\n\n## Acceptance Criteria\n\nIt is finished.\n") do |root|
        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "acceptance" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("maps 0/3 criteria")
      end
    end

    it "refuses a report that maps only some of them" do
      report = <<~MARKDOWN
        # M99-01

        ## Acceptance Criteria

        - [x] 1. The first thing — `spec/unit/first_spec.rb`.
        - [x] 2. The second thing — `spec/unit/second_spec.rb`.
      MARKDOWN

      with_milestone(story: story_declaring_three, report: report) do |root|
        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "acceptance" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("missing 3")
      end
    end

    it "refuses an unresolved Critical finding" do
      review = <<~MARKDOWN
        # Review — M99-01

        ### F-1 — The executor has no allowlist

        - **Severidade:** Critical
        - **Estado:** open
      MARKDOWN

      with_milestone(review: review) do |root|
        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "findings" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("Critical and High must be 0")
      end
    end

    # The glob was `review/*.json`, of which this repository has none. Eighteen
    # Markdown reviews sat next to it unread, every Story reported zero findings,
    # and a Story with no review at all reported the same thing.
    it "refuses a required Story with no review at all" do
      with_milestone do |root|
        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "findings" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("no implementation self-review for M99-01")
      end
    end

    it "reads the Markdown review the template defines" do
      review = <<~MARKDOWN
        # Review — M99-01

        ### F-1 — A nested run overwrote the outer run's evidence

        - **Severidade:** High (resolved)
      MARKDOWN

      with_milestone(review: review) do |root|
        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "findings" ]).run

        expect(runner).to be_ok
      end
    end
  end

  # AC5. No production credential may exist in the workspace at all.
  describe "a production credential in the workspace" do
    it "is checked before anything else runs against that workspace" do
      expect(described_class::CHECKS.first).to eq("workspace-clean")
    end

    it "is refused" do
      output, _status = run_gate("M00", "--only", "workspace-clean")
      report = JSON.parse(output)
      check = report["checks"].first

      # Green here means the workspace is clean, which is the state it must be
      # in. The guardrail's own negative cases live in its spec — this asserts
      # the Stop Gate consults it, and consults it first.
      expect(check["name"]).to eq("workspace-clean")
      expect(check["result"]).to eq("pass")
    end
  end

  # AC9, and the point of the whole file.
  describe "what the gate refuses to take on trust" do
    it "runs a command for every check instead of reading a claim" do
      source = File.read(File.join(STOP_GATE_ROOT, "lib/gates/stop_gate.rb"))

      # Nothing in here reads a "done" flag the agent wrote about itself: the
      # states it does read are cross-checked against a commit, a report or an
      # exit code.
      expect(source).to include("Open3.capture3")
      expect(source).to include("No check here is satisfiable by the agent saying so")
    end

    it "cannot be told to skip a check by an environment variable" do
      source = File.read(File.join(STOP_GATE_ROOT, "lib/gates/stop_gate.rb")) +
               File.read(File.join(STOP_GATE_ROOT, "bin/stop-gate"))

      expect(source).not_to match(/ENV\[["'](SKIP|FORCE|ALLOW|BYPASS)_?\w*["']\]/),
        "a gate that can be exported away is not a gate"
    end

    it "is owned, so editing it to unblock a Milestone needs a human" do
      codeowners = File.read(File.join(STOP_GATE_ROOT, ".github/CODEOWNERS"))

      expect(codeowners).to include("/lib/gates/")
    end
  end
end
