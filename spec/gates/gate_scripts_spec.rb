require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/gates/story_boundary"
require_relative "../../lib/gates/post_commit"
require_relative "../../lib/gates/related_specs"
require_relative "../support/gate_repository"

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
  def gate_root = @gate_root || File.expand_path("../..", __dir__)
  BOUNDARY = Opanel::Gates::StoryBoundary
  POST_COMMIT = Opanel::Gates::PostCommit

  def gate(*arguments, root: gate_root)
    Open3.capture2e("bin/gate", *arguments, chdir: root)
  end

  def gate_json(*arguments, root: gate_root)
    output, status = gate(*arguments, "--format", "json", root: root)
    [ JSON.parse(output), status ]
  end

  def check(report, name)
    report.fetch("checks").find { |entry| entry["check"] == name }
  end

  # M00-R18. The gate library asked `mktemp` for its results file. `mktemp -t
  # opanel-gate` is the BSD form: BSD appends the random suffix itself, GNU
  # coreutils requires the template to end in at least three X's and exits
  # non-zero without them. The CI runner is Ubuntu, so `gate_begin` died before a
  # single check ran — on every gate, on every push.
  #
  # A stand-in enforcing the GNU rule, so the portable form is proven rather than
  # assumed.
  describe "the results file the gate library creates" do
    def with_gnu_mktemp
      Dir.mktmpdir do |bin|
        stub = File.join(bin, "mktemp")
        File.write(stub, <<~SH)
          #!/bin/sh
          # GNU coreutils: -t is deprecated, and a template needs three X's.
          case "$1" in
            -*) echo "mktemp: the GNU form takes a template, not $1" >&2; exit 1 ;;
            *XXX*) exec /usr/bin/mktemp "$1" ;;
            *) echo "mktemp: too few X's in template '$1'" >&2; exit 1 ;;
          esac
        SH
        FileUtils.chmod(0o755, stub)

        yield({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" })
      end
    end

    it "uses a template GNU mktemp accepts, so the gate runs on the CI runner" do
      with_gnu_mktemp do |environment|
        output, status = Open3.capture2e(
          environment, "bash", "-c",
          "source bin/_gate_lib.sh; gate_begin probe text; gate_pass one ok; gate_finish",
          chdir: gate_root
        )

        expect(status).to be_success, output
        expect(output).to include("probe: PASS")
      end
    end

    it "is the stand-in that catches it: the BSD form fails against it" do
      with_gnu_mktemp do |environment|
        _output, status = Open3.capture2e(
          environment, "bash", "-c", "mktemp -t opanel-gate", chdir: gate_root
        )

        expect(status).not_to be_success,
          "the stand-in has to reject the old form, or this proves nothing"
      end
    end
  end

  # Genuinely staged, not `--intent-to-add`: the gate reads
  # `git diff --cached`, which does not list an intent-to-add entry, so a
  # probe added that way would never reach the check it is meant to trip.
  #
  # Held under RepositoryLock: this writes into the real working tree of
  # gate_root via `git add`/`git rm --cached`, which take `.git/index.lock`
  # and do not retry on contention — two workers racing there can make one
  # silently no-op. And under `bin/test --parallel` a full-tree scan running
  # in another worker (spec/security/security_scan_spec.rb) would otherwise
  # see the probe mid-flight and report a leak nobody here planted for it.
  def with_staged(path, contents)
    Opanel::Gates::GateRepository.with(gate_root) do |directory|
      @gate_root = directory
      full = File.join(directory, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, contents)
      _output, status = Open3.capture2e("git", "add", "--force", path, chdir: directory)
      raise "could not stage probe" unless status.success?

      yield
    ensure
      @gate_root = nil
    end
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
      source = File.read(File.join(gate_root, "bin/gate"))
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
        _output, status = Open3.capture2e("bin/format", "--check", chdir: gate_root)
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
        _output, status = Open3.capture2e("bin/lint", chdir: gate_root)
        expect(status).not_to be_success
      end
    end

    it "rejects a type error" do
      with_staged("app/frontend/gate-probe/broken.ts", "export const n: number = true\n") do
        _output, status = Open3.capture2e("bin/typecheck", chdir: gate_root)
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
          "bin/test", "spec/unit/gate_probe_failing_spec.rb", chdir: gate_root
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

      # `--staged`, not `--fast`: the token is planted in the index, and that is
      # the scope the pre-commit gate scans. Scanning the whole tree to find a
      # staged file cost 38 seconds and proved something broader than the claim.
      with_staged("config/ci/.gate-probe.env", "GITHUB_TOKEN=#{token}\n") do
        output, status = Open3.capture2e("bin/security", "--staged", chdir: gate_root)

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
        _output, status = Open3.capture2e("bin/migration-gate", chdir: gate_root)
        expect(status).not_to be_success
      end
    end

    # A stray artifact is not a style problem: it is how a dump, a key or a
    # customer's data reaches a repository by accident.
    it "rejects a staged build artifact" do
      # `--only`: the expectation reads one field, and running the other seven
      # checks to reach it cost 123 seconds — a full suite and a full tree scan
      # to assert that a staged .sqlite3 is rejected. The narrowed run proves the
      # same thing; the report marks the rest `skip`, so it cannot be mistaken
      # for a full pass.
      with_staged("config/gate-probe-artifact.sqlite3", "not really a database\n") do
        report, _status = gate_json("pre-commit", "--only", "no-stray-files", "--story", "M00-12")
        expect(check(report, "no-stray-files")["result"]).to eq("fail")
      end
    end

    # AC5: the boundary check, proved negatively.
    it "rejects a file outside the Story's declared boundary" do
      result = BOUNDARY.check("M00-12", [ "app/models/service.rb" ], gate_root)

      expect(result.status).to eq(:fail)
      expect(result.reason).to include("outside the boundary of M00-12")
      expect(result.outside).to eq([ "app/models/service.rb" ])
    end

    it "accepts a file inside it" do
      expect(BOUNDARY.check("M00-12", [ "bin/gate" ], gate_root).status).to eq(:pass)
    end

    # `.github/**` reads as "everything under .github", and has to behave that
    # way: Ruby's fnmatch only recurses through `**/`, so the bare form silently
    # rejected files the boundary plainly allowed.
    it "reads a trailing ** as everything underneath, at any depth" do
      files = [ ".github/CODEOWNERS", ".github/workflows/ci.yml",
                ".github/actions/archive/action.yml" ]

      expect(BOUNDARY.check("M00-11", files, gate_root).status).to eq(:pass)
    end

    # Always-allowed paths: a Story that could not record its own state would be
    # unable to finish.
    it "accepts the pack's own bookkeeping without declaring it" do
      files = [ "docs/implementation/M00/tasks.json", "docs/implementation/M00/reports/M00-12.md" ]

      expect(BOUNDARY.check("M00-12", files, gate_root).status).to eq(:pass)
    end

    # The check must not be satisfiable by declaring nothing.
    it "fails an undeclared Story rather than waving it through" do
      result = BOUNDARY.check("M99-01", [ "app/models/service.rb" ], gate_root)

      expect(result.status).to eq(:fail)
      expect(result.reason).to include("declares no boundary")
    end
  end

  # Annex I §11.1 asks for the *related* tests. `--changed` selected changed spec
  # files and nothing else, and exited 0 with "no spec file changed" whenever a
  # commit touched only source — so the shape of commit where running the suite
  # matters most was the shape where none ran, and the gate recorded `tests PASS`.
  describe "the related specs" do
    RELATED = Opanel::Gates::RelatedSpecs

    def selection_for(*changed) = RELATED.for_changed(changed, root: gate_root)

    it "selects a changed spec directly" do
      selection = selection_for("spec/unit/application_job_spec.rb")

      expect(selection.paths).to eq([ "spec/unit/application_job_spec.rb" ])
      expect(selection.uncovered).to be_empty
    end

    it "selects the spec named after a changed source file" do
      expect(selection_for("app/jobs/application_job.rb").paths)
        .to include("spec/unit/application_job_spec.rb")
    end

    it "falls back to the suite that would notice, when nothing is named after the file" do
      expect(selection_for("db/migrate/20260101000000_probe.rb").paths)
        .to include("spec/gates/migration_gate_spec.rb")
    end

    # "There was nothing to run" and "everything passed" are not the same answer.
    it "reports application code no spec and no suite covers" do
      selection = selection_for("app/mcp/tool_registry.rb")

      expect(selection.paths).to be_empty
      expect(selection.uncovered).to eq([ "app/mcp/tool_registry.rb" ])
    end

    it "ignores what RSpec cannot be selected for" do
      selection = selection_for("docs/MASTER.md", "app/frontend/pages/Home.tsx", "package.json")

      expect(selection.paths).to be_empty
      expect(selection.uncovered).to be_empty
    end

    it "exits non-zero rather than selecting nothing" do
      output, status = Open3.capture2e(
        "ruby", "lib/gates/related_specs.rb",
        stdin_data: "app/mcp/tool_registry.rb\n", chdir: gate_root
      )

      expect(status).not_to be_success
      expect(output).to include("no spec is related to app/mcp/tool_registry.rb")
    end
  end

  describe "the git hook" do
    # AC4.
    it "is installed by bin/setup" do
      expect(File.read(File.join(gate_root, "bin/setup"))).to include("bin/install-hooks")
    end

    it "is versioned, so a change to it is reviewable" do
      hook = File.join(gate_root, ".githooks/pre-commit")

      expect(File.exist?(hook)).to be(true)
      expect(File.executable?(hook)).to be(true)
      expect(File.read(hook)).to include("bin/gate pre-commit")
    end

    # This asserted that *this* machine had core.hooksPath set — true on a
    # developer's checkout because bin/setup had run, and false on a CI runner,
    # where it failed the `unit` job on the first real execution of the pipeline.
    # Asserting the ambient state proves only that somebody once ran the script.
    # What has to hold everywhere is the round trip: --check refuses a repository
    # that is not configured, and bin/install-hooks configures it.
    #
    # GIT_DIR/GIT_WORK_TREE point git at a scratch repository, so the example
    # proves both directions without ever touching the hooks of the checkout it
    # runs in — a test that unset them and died would silently disable the gate.
    it "is what git is configured to run, once bin/install-hooks has run" do
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", directory)
        env = { "GIT_DIR" => File.join(directory, ".git"), "GIT_WORK_TREE" => directory }

        refused, refused_status = Open3.capture2e(env, "bin/install-hooks", "--check", chdir: gate_root)

        expect(refused_status).not_to be_success
        expect(refused).to include("unset")

        Open3.capture2e(env, "bin/install-hooks", chdir: gate_root)
        output, status = Open3.capture2e(env, "bin/install-hooks", "--check", chdir: gate_root)

        expect(status).to be_success, output
        expect(output).to include(".githooks")
      end
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

    # A scratch repository with one commit, and whatever pre-commit record the
    # example wants beside it.
    def with_recorded_commit(record)
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        Open3.capture2e("git", "-c", "user.email=t@example.com", "-c", "user.name=T",
          "commit", "--allow-empty", "--quiet", "-m", "probe", chdir: directory)
        tree, = Open3.capture2e("git", "rev-parse", "HEAD^{tree}", chdir: directory)
        tree = tree.strip

        FileUtils.mkdir_p(File.join(directory, POST_COMMIT::EVIDENCE_DIRECTORY))
        File.write(
          File.join(directory, POST_COMMIT::EVIDENCE_DIRECTORY, "pre-commit-#{tree}.json"),
          JSON.generate(record.call(tree))
        )

        yield POST_COMMIT.run("pre-commit-executed", story: "M00-12", root: directory)
      end
    end

    def complete_record
      lambda do |tree|
        { gate: "pre-commit", tree: tree, result: "pass",
          checks: POST_COMMIT::PRE_COMMIT_CHECKS, at: "2026-09-06T00:00:00Z" }
      end
    end

    it "is not detected when the record exists" do
      with_recorded_commit(complete_record) { |outcome| expect(outcome).to be_ok }
    end

    # The record used to be written at the end of every run, whatever the run
    # found. A red pre-commit gate produced a certificate for a tree it had just
    # rejected, and this check — the one that exists to catch a bypass — read it
    # and passed.
    it "refuses a record whose own result was a failure" do
      record = ->(tree) { complete_record.call(tree).merge(result: "fail") }

      with_recorded_commit(record) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("already failed")
      end
    end

    it "refuses a record that does not name every item of §12.1" do
      record = ->(tree) { complete_record.call(tree).merge(checks: %w[format lint]) }

      with_recorded_commit(record) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("secret-scan")
      end
    end

    it "refuses a record describing another tree" do
      record = ->(_tree) { complete_record.call("0" * 40) }

      with_recorded_commit(record) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("describes something else")
      end
    end

    it "is written only by a gate that passed" do
      source = File.read(File.join(gate_root, "bin/gate"))
      recorder = source[/record_pre_commit_evidence\(\) \{(.*?)^\}/m]

      expect(recorder).to include("GATE_FAILURES"),
        "the recorder must consult the run's result before attesting to it"
    end

    it "is written by the gate itself, keyed by the tree" do
      expect(File.read(File.join(gate_root, "bin/gate")))
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
      expect(File.read(File.join(gate_root, ".githooks/pre-commit"))).to include("--no-verify")

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

    # A scratch repository whose HEAD the evidence can honestly name.
    def with_test_evidence(metadata, story: "M99-01", story_body: nil)
      Dir.mktmpdir do |directory|
        Open3.capture2e("git", "init", "--quiet", chdir: directory)
        Open3.capture2e("git", "-c", "user.email=t@example.com", "-c", "user.name=T",
          "commit", "--allow-empty", "--quiet", "-m", "probe", chdir: directory)
        head, = Open3.capture2e("git", "rev-parse", "HEAD", chdir: directory)

        if story_body
          FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/stories"))
          File.write(File.join(directory, "docs/implementation/M99/stories/#{story}-probe.md"), story_body)
        end

        FileUtils.mkdir_p(File.join(directory, "tmp/test-results"))
        File.write(
          File.join(directory, "tmp/test-results/rspec-metadata.json"),
          JSON.generate({ "result" => "pass", "commit" => head.strip }.merge(metadata))
        )

        yield POST_COMMIT.run("tests", story: story, root: directory)
      end
    end

    # An empty run reports `pass` for the same reason a green suite does. The
    # gate read only that field, so a run that executed nothing was evidence.
    it "refuses a run that executed no examples" do
      with_test_evidence({ "type" => "all", "tests" => 0 }) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("executed no examples")
      end
    end

    it "refuses evidence that contradicts itself" do
      with_test_evidence({ "type" => "all", "tests" => 12, "failures" => 3 }) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("contradicts itself")
      end
    end

    # The evidence in the tree was from a `contract` run, and it was accepted for
    # a Story whose Required Tests name unit, integration and security. Evidence
    # from a narrower run is evidence about something else.
    it "refuses evidence from a suite the Story does not declare" do
      story = <<~MARKDOWN
        # M99-01 — Probe

        ## Required Tests
        - **unit**: the rules.
        - **integration**: against real PostgreSQL.

        ## Quality Gates
        Local.
      MARKDOWN

      with_test_evidence({ "type" => "contract", "tests" => 4 }, story_body: story) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("unit", "integration")
      end
    end

    it "accepts a full run for the same Story" do
      story = <<~MARKDOWN
        # M99-01 — Probe

        ## Required Tests
        - **unit**: the rules.
        - **integration**: against real PostgreSQL.
      MARKDOWN

      with_test_evidence({ "type" => "all", "scope" => "all", "fast" => false, "complete" => true,
                           "selected_paths" => [], "tests" => 40 }, story_body: story) do |outcome|
        expect(outcome).to be_ok
      end
    end

    # M00-R06. `type` stayed `all` however the run had been narrowed, and the gate
    # read `all` as "every suite ran". A Story declaring six suites was cleared by
    # a run of three spec files.
    describe "a run that was narrowed" do
      let(:story) do
        <<~MARKDOWN
          # M99-01 — Probe

          ## Required Tests
          - **unit**: the rules.
          - **integration**: against real PostgreSQL.
        MARKDOWN
      end

      {
        "--changed" => { "scope" => "changed", "selected_paths" => [ "spec/unit/a_spec.rb" ] },
        "--fast" => { "fast" => true },
        "a path" => { "selected_paths" => [ "spec/unit/a_spec.rb" ] }
      }.each do |narrowing, fields|
        it "refuses evidence from a run narrowed by #{narrowing}" do
          metadata = { "type" => "all", "scope" => "all", "fast" => false, "selected_paths" => [],
                       "complete" => false, "tests" => 40 }.merge(fields)

          with_test_evidence(metadata, story_body: story) do |outcome|
            expect(outcome).not_to be_ok
            expect(outcome.reason).to include("unit", "integration")
          end
        end
      end

      # A `--type integration` run is narrow and honest about it: it covers that
      # suite and says nothing about the others.
      it "credits a whole-type run for the type it ran" do
        metadata = { "type" => "integration", "scope" => "all", "fast" => false,
                     "selected_paths" => [ "spec/integration" ], "complete" => false, "tests" => 40 }
        integration_only = "# M99-01 — Probe\n\n## Required Tests\n- **integration**: real PostgreSQL.\n"

        with_test_evidence(metadata, story_body: integration_only) do |outcome|
          expect(outcome).to be_ok
        end
      end

      it "refuses evidence written before the selection was recorded" do
        with_test_evidence({ "type" => "all", "tests" => 40 }, story_body: story) do |outcome|
          expect(outcome).not_to be_ok
          expect(outcome.reason).to include("before the run's selection was recorded")
        end
      end
    end

    # A skipped example reports `pass` for the same reason a green one does.
    it "refuses a run that skipped examples" do
      with_test_evidence({ "type" => "all", "scope" => "all", "fast" => false, "complete" => true,
                           "selected_paths" => [], "tests" => 40, "skipped" => 9 }) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("skipped 9 example(s)")
      end
    end
  end

  # M00-18's templates describe a report that maps every criterion. The gate
  # checked that the word "acceptance" appeared, which a report mapping three of
  # nine criteria also does.
  describe "the acceptance mapping" do
    # The referenced specs are created, because the gate now asks whether the
    # evidence points at anything. A report naming a file nobody wrote is the
    # declaratory case, and it has its own example below.
    def with_story_and_report(story_body, report_body, files: %w[
      spec/unit/first_spec.rb spec/unit/second_spec.rb spec/unit/third_spec.rb
    ])
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/stories"))
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/reports"))
        File.write(File.join(directory, "docs/implementation/M99/stories/M99-01-probe.md"), story_body)
        File.write(File.join(directory, "docs/implementation/M99/reports/M99-01.md"), report_body)

        files.each do |path|
          full = File.join(directory, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, "# probe\n")
        end

        yield POST_COMMIT.run("acceptance-mapping", story: "M99-01", root: directory)
      end
    end

    let(:story) do
      <<~MARKDOWN
        # M99-01 — Probe

        ## Acceptance Criteria
        1. The first thing happens.
        2. The second thing happens.
        3. The third thing happens.

        ## Required Tests
        - **unit**: the rules.
      MARKDOWN
    end

    it "refuses a report that maps only some of the criteria" do
      report = <<~MARKDOWN
        # Story Report — M99-01

        ## Acceptance Criteria

        - [x] 1. The first thing — `spec/unit/first_spec.rb`.
      MARKDOWN

      with_story_and_report(story, report) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("1 of 3")
        expect(outcome.reason).to include("2, 3")
      end
    end

    it "refuses a criterion that is neither satisfied nor deferred to a decision" do
      report = <<~MARKDOWN
        # Story Report — M99-01

        ## Acceptance Criteria

        - [x] 1. The first thing — `spec/unit/first_spec.rb`.
        - [x] 2. The second thing — `spec/unit/second_spec.rb`.
        - [ ] 3. The third thing did not get done.
      MARKDOWN

      with_story_and_report(story, report) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("neither satisfied by evidence that exists")
      end
    end

    it "accepts one deferred to a named decision" do
      report = <<~MARKDOWN
        # Story Report — M99-01

        ## Acceptance Criteria

        - [x] 1. The first thing — `spec/unit/first_spec.rb`.
        - [x] 2. The second thing — `spec/unit/second_spec.rb`.
        - [ ] 3. **Deferred.** Waits on ADR-0002, which is still Proposed.
      MARKDOWN

      with_story_and_report(story, report, files: %w[
        spec/unit/first_spec.rb spec/unit/second_spec.rb docs/decisions/adr-0002-identifiers.md
      ]) { |outcome| expect(outcome).to be_ok }
    end

    it "accepts the table form the template offers" do
      report = <<~MARKDOWN
        # Story Report — M99-01

        ## Acceptance Criteria

        | # | Critério | Evidência |
        |---|---|---|
        | 1 | The first thing | `spec/unit/first_spec.rb` |
        | 2 | The second thing | `spec/unit/second_spec.rb` |
        | 3 | The third thing | `spec/unit/third_spec.rb` |
      MARKDOWN

      with_story_and_report(story, report) { |outcome| expect(outcome).to be_ok }
    end

    # M00-R07. A ticked box and a non-empty cell are things the author writes
    # about their own work. The Autonomous Loop writes them for every criterion,
    # which is why the tick cannot be the evidence.
    describe "evidence that points at nothing" do
      it "refuses a claim with no reference at all" do
        report = <<~MARKDOWN
          # Story Report — M99-01

          ## Acceptance Criteria

          | # | Critério | Evidência |
          |---|---|---|
          | 1 | The first thing | done |
          | 2 | The second thing | works as specified |
          | 3 | The third thing | verified manually |
        MARKDOWN

        with_story_and_report(story, report) do |outcome|
          expect(outcome).not_to be_ok
          expect(outcome.reason).to include("evidence points at nothing that exists")
        end
      end

      it "refuses a claim naming a file nobody wrote" do
        report = <<~MARKDOWN
          # Story Report — M99-01

          ## Acceptance Criteria

          | # | Critério | Evidência |
          |---|---|---|
          | 1 | The first thing | `spec/unit/first_spec.rb` |
          | 2 | The second thing | `spec/unit/second_spec.rb` |
          | 3 | The third thing | `spec/unit/imagined_spec.rb` |
        MARKDOWN

        with_story_and_report(story, report) do |outcome|
          expect(outcome).not_to be_ok
          expect(outcome.reason).to include("3 (evidence points at nothing that exists)")
        end
      end

      it "refuses a deferral to a decision nobody wrote" do
        report = <<~MARKDOWN
          # Story Report — M99-01

          ## Acceptance Criteria

          - [x] 1. The first thing — `spec/unit/first_spec.rb`.
          - [x] 2. The second thing — `spec/unit/second_spec.rb`.
          - [ ] 3. **Deferred.** Waits on ADR-0099, which does not exist.
        MARKDOWN

        with_story_and_report(story, report) do |outcome|
          expect(outcome).not_to be_ok
          expect(outcome.reason).to include("nor deferred to an ADR or Story that exists")
        end
      end

      # A criterion proven by a test rather than by a file: the sentence either is
      # in the suites or it is not, and that is checkable without running them.
      it "accepts a claim quoting a test that exists" do
        report = <<~MARKDOWN
          # Story Report — M99-01

          ## Acceptance Criteria

          | # | Critério | Evidência |
          |---|---|---|
          | 1 | The first thing | `"rejects an unsigned webhook"` |
          | 2 | The second thing | `spec/unit/second_spec.rb` |
          | 3 | The third thing | `spec/unit/third_spec.rb` |
        MARKDOWN

        Dir.mktmpdir do |directory|
          FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/stories"))
          FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/reports"))
          FileUtils.mkdir_p(File.join(directory, "spec/unit"))
          File.write(File.join(directory, "docs/implementation/M99/stories/M99-01-probe.md"), story)
          File.write(File.join(directory, "docs/implementation/M99/reports/M99-01.md"), report)
          File.write(File.join(directory, "spec/unit/second_spec.rb"), "# probe\n")
          File.write(File.join(directory, "spec/unit/third_spec.rb"), "# probe\n")
          File.write(File.join(directory, "spec/unit/webhook_spec.rb"),
            %(it "rejects an unsigned webhook" do\nend\n))

          expect(POST_COMMIT.run("acceptance-mapping", story: "M99-01", root: directory)).to be_ok
        end
      end
    end
  end

  # An absent review is not a clean one. The check globbed `review/*.json`, of
  # which this repository has none, so every Story reported zero findings —
  # including a Story with no review at all.
  describe "the reviewer findings" do
    def with_review(contents)
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "docs/implementation/M99/review"))
        if contents
          File.write(File.join(directory, "docs/implementation/M99/review/M99-01.md"), contents)
        end

        yield POST_COMMIT.run("reviewer-findings", story: "M99-01", root: directory)
      end
    end

    it "refuses a Story with no review at all" do
      with_review(nil) do |outcome|
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("an absent review is not a clean one")
      end
    end

    it "reads the Markdown form the template defines" do
      with_review(<<~MARKDOWN) do |outcome|
        # Review — M99-01

        ## Findings

        ### F-1 — Authorization is missing on the delete path

        - **Dimensão:** Segurança
        - **Severidade:** High
        - **Evidência:** `app/commands/delete.rb:12`
        - **Estado:** open
      MARKDOWN
        expect(outcome).not_to be_ok
        expect(outcome.reason).to include("Critical and High must be 0")
        expect(outcome.reason).to include("F-1")
      end
    end

    it "accepts a High that was resolved inside the Story" do
      with_review(<<~MARKDOWN) { |outcome| expect(outcome).to be_ok }
        # Review — M99-01

        ## Findings

        ### F-1 — A nested run overwrote the outer run's evidence

        - **Dimensão:** Correção
        - **Severidade:** High (resolved)
        - **Evidência:** `bin/test:70`
      MARKDOWN
    end

    it "accepts a Medium left open with its reason" do
      with_review(<<~MARKDOWN) { |outcome| expect(outcome).to be_ok }
        # Review — M99-01

        ## Findings

        ### F-1 — The scan was narrowed to the staged diff

        - **Dimensão:** Segurança
        - **Severidade:** Medium
        - **Estado:** open, with CI compensating
      MARKDOWN
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
      merge_gate = File.read(File.join(gate_root, "bin/merge-gate"))

      expect(merge_gate).to include("bin/gate")
      expect(File.read(File.join(gate_root, ".github/CODEOWNERS"))).to include("/lib/gates/")
    end
  end
end
