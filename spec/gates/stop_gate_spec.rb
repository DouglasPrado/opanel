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

    # An acceptance criterion that points at nothing is not satisfied, and the
    # report is where it points.
    it "refuses a done Story whose report maps no acceptance criteria" do
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99")
        FileUtils.mkdir_p(File.join(directory, "reports"))
        File.write(File.join(directory, "tasks.json"), JSON.generate(stories: [
          { "id" => "M99-01", "status" => "done", "required" => true, "commit" => "a1b2c3d" }
        ]))
        File.write(File.join(directory, "reports/M99-01.md"), "# M99-01\n\nIt is finished.\n")

        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "acceptance" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("no acceptance mapping")
      end
    end

    it "refuses an unresolved Critical finding" do
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99/review")
        FileUtils.mkdir_p(directory)
        File.write(File.join(directory, "M99-01.json"), JSON.generate(
          findings: [ { "severity" => "critical", "title" => "the executor has no allowlist" } ]
        ))

        runner = described_class::Runner.new(milestone: "M99", root: root, only: [ "findings" ]).run

        expect(runner).not_to be_ok
        expect(runner.reason).to include("Critical and High must be 0")
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
