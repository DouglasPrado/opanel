require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require_relative "../../lib/gates/story_boundary"
require_relative "../../lib/gates/post_commit"

# The three local gates, proved by breaking them.
#
# A gate nobody proved can fail is a gate that passes forever, and these are the
# ones standing between an autonomous loop and a bad commit. So each of the eight
# Pre-commit items of Annex I §12.1 is planted with the failure it exists to
# catch, and has to reject it.
#
# The checks run against a scratch repository rather than this one wherever they
# can: a gate that only works in the tree that produced it has not been tested,
# it has been observed.
RSpec.describe "The local gates", :slow do
  GATE_ROOT = File.expand_path("../..", __dir__)
  BOUNDARY = Opanel::Gates::StoryBoundary
  POST_COMMIT = Opanel::Gates::PostCommit

  def gate(*arguments, root: GATE_ROOT)
    Open3.capture2e("bin/gate", *arguments, chdir: root)
  end

  def gate_json(*arguments, root: GATE_ROOT)
    output, status = gate(*arguments, "--format", "json", root: root)
    [ JSON.parse(output), status ]
  end

  def check(report, name)
    report.fetch("checks").find { |entry| entry["check"] == name }
  end

  # Genuinely staged, not `--intent-to-add`: the gate reads
  # `git diff --cached`, which does not list an intent-to-add entry, so a
  # probe added that way would never reach the check it is meant to trip.
  def with_staged(path, contents)
    full = File.join(GATE_ROOT, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
    Open3.capture2e("git", "add", "--force", path, chdir: GATE_ROOT)
    yield
  ensure
    Open3.capture2e("git", "rm", "--cached", "--force", "--quiet", path, chdir: GATE_ROOT)
    FileUtils.rm_f(full)
    directory = File.dirname(full)
    FileUtils.rmdir(directory) if Dir.exist?(directory) && Dir.empty?(directory)
  end


  describe "the entry points" do
    it "offers local, pre-commit and post-commit, and refuses anything else" do
      output, status = gate("nonsense")

      expect(status).not_to be_success
      expect(output).to include("local", "pre-commit", "post-commit")
    end

    # AC7. The loop parses this; a human reads the text form. Both come from the
    # same run.
    it "reports each check with a name, a result, a duration and a reason" do
      report, _status = gate_json("post-commit", "--story", "M00-11")

      expect(report["gate"]).to eq("gate:post-commit")
      expect(report["checks"]).to all(include("check", "result", "duration_ms", "reason"))
      expect(report["duration_ms"]).to be_a(Integer)
    end

    it "runs the eight items of Annex I §12.1, in order" do
      source = File.read(File.join(GATE_ROOT, "bin/gate"))
      pre_commit = source[/^  pre-commit\)(.*?)^    ;;/m]

      %w[format lint typecheck tests secret-scan migrations no-stray-files diff-boundary]
        .each_cons(2) do |earlier, later|
          expect(pre_commit.index(%("#{earlier}"))).to be < pre_commit.index(%("#{later}")),
            "#{earlier} must run before #{later}"
        end
    end

    it "runs the six checks of Annex I §14.2" do
      report, _status = gate_json("post-commit", "--story", "M00-11")
      names = report["checks"].map { |entry| entry["check"] }

      expect(names).to include(
        "diff-review", "acceptance-mapping", "reviewer-findings",
        "fitness", "tests", "state"
      )
    end
  end

  # AC2: one negative case per Pre-commit item. Each is exercised through the
  # command the gate actually runs, so a change to the gate's wiring breaks these
  # rather than sliding past them.
  describe "each Pre-commit item rejects what it exists to catch" do
    it "rejects unformatted Ruby" do
      with_staged("lib/opanel/gate_probe_format.rb", "x  =  1\nputs   x\n") do
        _output, status = Open3.capture2e("bin/format", "--check", chdir: GATE_ROOT)
        expect(status).not_to be_success
      end
    end

    it "rejects a lint offence" do
      with_staged("lib/opanel/gate_probe_lint.rb", <<~RUBY) do
        # frozen_string_literal: true
        def probe
          a = 1
            b = 2
          a+b
        end
      RUBY
        _output, status = Open3.capture2e("bin/lint", chdir: GATE_ROOT)
        expect(status).not_to be_success
      end
    end

    it "rejects a type error" do
      with_staged("app/frontend/gate-probe/broken.ts", "export const n: number = true\n") do
        _output, status = Open3.capture2e("bin/typecheck", chdir: GATE_ROOT)
        expect(status).not_to be_success
      end
    end

    it "rejects a failing related test" do
      with_staged("spec/unit/gate_probe_failing_spec.rb", <<~RUBY) do
        require "spec_helper"

        RSpec.describe "a deliberately failing example" do
          it "fails" do
            expect(true).to be(false)
          end
        end
      RUBY
        _output, status = Open3.capture2e(
          "bin/test", "spec/unit/gate_probe_failing_spec.rb", chdir: GATE_ROOT
        )
        expect(status).not_to be_success
      end
    end

    it "rejects a secret, and does not print it" do
      skip "gitleaks is not installed" unless system("command -v gitleaks > /dev/null 2>&1")

      # Fragments, so this spec file holds no string the scanner recognises; and
      # a fixed value, because a random one crosses the entropy threshold only
      # sometimes and a flaky security test is a defect.
      token = "ghp_" + ("hR3xQ9wLmT7bVzN2yKfJ4sCdA8eUpG" + "1oX5i")

      with_staged("config/ci/.gate-probe.env", "GITHUB_TOKEN=#{token}\n") do
        output, status = Open3.capture2e("bin/security", "--fast", chdir: GATE_ROOT)

        expect(status).not_to be_success
        expect(output).not_to include(token)
      end
    end

    it "rejects an obviously invalid migration" do
      with_staged("db/migrate/29990102000000_gate_probe.rb", <<~RUBY) do
        class GateProbe < ActiveRecord::Migration[8.1]
          def up
            remove_column :infrastructure_checkpoints, :name
          end
        end
      RUBY
        _output, status = Open3.capture2e("bin/migration-gate", chdir: GATE_ROOT)
        expect(status).not_to be_success
      end
    end

    # A stray artifact is not a style problem: it is how a dump, a key or a
    # customer's data reaches a repository by accident.
    it "rejects a staged build artifact" do
      with_staged("config/gate-probe-artifact.sqlite3", "not really a database\n") do
        report, _status = gate_json("pre-commit", "--story", "M00-12")
        expect(check(report, "no-stray-files")["result"]).to eq("fail")
      end
    end

    # AC5: the boundary check, proved negatively.
    it "rejects a file outside the Story's declared boundary" do
      result = BOUNDARY.check("M00-12", [ "app/models/service.rb" ], GATE_ROOT)

      expect(result.status).to eq(:fail)
      expect(result.reason).to include("outside the boundary of M00-12")
      expect(result.outside).to eq([ "app/models/service.rb" ])
    end

    it "accepts a file inside it" do
      expect(BOUNDARY.check("M00-12", [ "bin/gate" ], GATE_ROOT).status).to eq(:pass)
    end

    # `.github/**` reads as "everything under .github", and has to behave that
    # way: Ruby's fnmatch only recurses through `**/`, so the bare form silently
    # rejected files the boundary plainly allowed.
    it "reads a trailing ** as everything underneath, at any depth" do
      files = [ ".github/CODEOWNERS", ".github/workflows/ci.yml",
                ".github/actions/archive/action.yml" ]

      expect(BOUNDARY.check("M00-11", files, GATE_ROOT).status).to eq(:pass)
    end

    # Always-allowed paths: a Story that could not record its own state would be
    # unable to finish.
    it "accepts the pack's own bookkeeping without declaring it" do
      files = [ "docs/implementation/M00/tasks.json", "docs/implementation/M00/reports/M00-12.md" ]

      expect(BOUNDARY.check("M00-12", files, GATE_ROOT).status).to eq(:pass)
    end

    # The check must not be satisfiable by declaring nothing.
    it "fails an undeclared Story rather than waving it through" do
      result = BOUNDARY.check("M99-01", [ "app/models/service.rb" ], GATE_ROOT)

      expect(result.status).to eq(:fail)
      expect(result.reason).to include("declares no boundary")
    end
  end

  describe "the git hook" do
    # AC4.
    it "is installed by bin/setup" do
      expect(File.read(File.join(GATE_ROOT, "bin/setup"))).to include("bin/install-hooks")
    end

    it "is versioned, so a change to it is reviewable" do
      hook = File.join(GATE_ROOT, ".githooks/pre-commit")

      expect(File.exist?(hook)).to be(true)
      expect(File.executable?(hook)).to be(true)
      expect(File.read(hook)).to include("bin/gate pre-commit")
    end

    it "is what git is configured to run" do
      output, status = Open3.capture2e("bin/install-hooks", "--check", chdir: GATE_ROOT)

      expect(status).to be_success, output
      expect(output).to include(".githooks")
    end
  end

  # AC6. `--no-verify` leaves no trace in a commit; what it leaves is the absence
  # of one.
  describe "a bypassed gate" do
    it "is detected, because the hook records the tree it checked" do
      Dir.mktmpdir do |directory|
        # A real commit with no evidence beside it: exactly what `--no-verify`
        # leaves behind.
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        Open3.capture2e("git", "-c", "user.email=t@example.com", "-c", "user.name=T",
          "commit", "--allow-empty", "--quiet", "-m", "bypassed", chdir: directory)

        outcome = POST_COMMIT.run("pre-commit-executed", story: "M00-12", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("--no-verify")
      end
    end

    it "is not detected when the record exists" do
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        Open3.capture2e("git", "-c", "user.email=t@example.com", "-c", "user.name=T",
          "commit", "--allow-empty", "--quiet", "-m", "probe", chdir: directory)
        tree, = Open3.capture2e("git", "rev-parse", "HEAD^{tree}", chdir: directory)

        FileUtils.mkdir_p(File.join(directory, POST_COMMIT::EVIDENCE_DIRECTORY))
        File.write(
          File.join(directory, POST_COMMIT::EVIDENCE_DIRECTORY, "pre-commit-#{tree.strip}.json"),
          JSON.generate(tree: tree.strip, gate: "pre-commit")
        )

        expect(POST_COMMIT.run("pre-commit-executed", story: "M00-12", root: directory)).to be_ok
      end
    end

    it "is written by the gate itself, keyed by the tree" do
      expect(File.read(File.join(GATE_ROOT, "bin/gate")))
        .to include("record_pre_commit_evidence")
    end

    it "is refused by the repository: nothing that runs passes --no-verify to git" do
      report, _status = gate_json("post-commit", "--story", "M00-11")

      expect(check(report, "no-verify-absent")["result"]).to eq("pass")
    end

    # The check has to tell a use from a mention. Both the hook and the
    # post-commit gate name the flag in order to forbid it, and a checker that
    # reports the sentence explaining the rule is one people learn to ignore.
    it "is not tripped by prose that names the flag in order to forbid it" do
      expect(File.read(File.join(GATE_ROOT, ".githooks/pre-commit"))).to include("--no-verify")

      report, _status = gate_json("post-commit", "--story", "M00-11")

      expect(check(report, "no-verify-absent")["result"]).to eq("pass")
    end

    it "is tripped by a script that actually passes it to git" do
      with_staged("bin/gate-probe-bypass", "#!/usr/bin/env bash\ngit commit --no-verify\n") do
        report, _status = gate_json("post-commit", "--story", "M00-11")

        expect(check(report, "no-verify-absent")["result"]).to eq("fail")
        expect(check(report, "no-verify-absent")["reason"]).to include("gate-probe-bypass")
      end
    end
  end

  describe "the Post-commit Gate" do
    # AC3: an objective reason, not "something is wrong".
    it "names the inconsistency when tasks.json disagrees with the commit" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99"))
        File.write(
          File.join(directory, "docs/implementation/M99/tasks.json"),
          JSON.generate(stories: [ { "id" => "M99-01", "status" => "done" } ])
        )

        outcome = POST_COMMIT.run("state", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("done with no commit hash")
      end
    end

    it "refuses a Story marked done whose commit is not in the repository" do
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99"))
        File.write(
          File.join(directory, "docs/implementation/M99/tasks.json"),
          JSON.generate(stories: [ { "id" => "M99-01", "status" => "done", "commit" => "deadbee" } ])
        )

        outcome = POST_COMMIT.run("state", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("not in this repository")
      end
    end

    it "refuses a Story still in progress" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99"))
        File.write(
          File.join(directory, "docs/implementation/M99/tasks.json"),
          JSON.generate(stories: [ { "id" => "M99-01", "status" => "in_progress" } ])
        )

        outcome = POST_COMMIT.run("state", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("does not close it")
      end
    end

    it "refuses a Story with no report mapping its acceptance criteria" do
      Dir.mktmpdir do |directory|
        outcome = POST_COMMIT.run("acceptance-mapping", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("no report at")
      end
    end

    # Critical and High block DONE and block merge.
    it "refuses an unresolved Critical finding" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/review"))
        File.write(
          File.join(directory, "docs/implementation/M99/review/M99-01.json"),
          JSON.generate(findings: [ { "severity" => "critical", "title" => "no authorization" } ])
        )

        outcome = POST_COMMIT.run("reviewer-findings", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("Critical and High must be 0")
      end
    end

    # Evidence, not a claim: the suite has to have been run against what was
    # committed.
    it "refuses test evidence from a different commit" do
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        Open3.capture2e("git", "-c", "user.email=t@example.com", "-c", "user.name=T",
          "commit", "--allow-empty", "--quiet", "-m", "probe", chdir: directory)
        FileUtils.mkdir_p(File.join(directory, "tmp/test-results"))
        File.write(
          File.join(directory, "tmp/test-results/rspec-metadata.json"),
          JSON.generate(result: "pass", commit: "0badc0de")
        )

        outcome = POST_COMMIT.run("tests", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("re-run the suite against what was committed")
      end
    end

    it "refuses a run that was never made" do
      Dir.mktmpdir do |directory|
        outcome = POST_COMMIT.run("tests", story: "M99-01", root: directory)

        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("a suite nobody ran is not a suite that passed")
      end
    end
  end

  describe "the gates themselves" do
    it "print no sensitive value" do
      report, _status = gate_json("post-commit", "--story", "M00-11")
      serialised = JSON.generate(report)

      # The reasons name files, rules and counts. A gate that echoed the secret
      # it found would publish it into every CI log that ran it.
      expect(serialised).not_to match(/ghp_[A-Za-z0-9]{20,}/)
      expect(serialised).not_to match(/-----BEGIN [A-Z ]*PRIVATE KEY-----/)
    end

    it "may not be edited to make a Story pass" do
      merge_gate = File.read(File.join(GATE_ROOT, "bin/merge-gate"))

      expect(merge_gate).to include("bin/gate")
      expect(File.read(File.join(GATE_ROOT, ".github/CODEOWNERS"))).to include("/lib/gates/")
    end
  end
end
