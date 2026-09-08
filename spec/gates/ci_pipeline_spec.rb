require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "../../lib/gates/ci_pipeline"

# The pipeline, proved rather than described.
#
# A CI configuration is usually only testable by pushing, which means it is
# usually not tested — and the parts that matter are the *negative* ones: what
# does a red typecheck actually block? So the pipeline's definition lives in
# config/ci/jobs.yml, the workflows only schedule it, and the checks below run
# the same commands CI runs against deliberately broken input.
#
# Each of the five failure classes of the Story's acceptance criteria (2–6) is
# planted and must block. A gate nobody proved can fail is a gate that passes
# forever.
RSpec.describe "The CI pipeline", :slow do
  PIPELINE_ROOT = File.expand_path("../..", __dir__)
  PIPELINE = Opanel::Gates::CiPipeline

  def run(*command, **options)
    Open3.capture2e(*command, chdir: PIPELINE_ROOT, **options)
  end

  # A file placed in the working tree, removed however the example ends.
  #
  # The probes have to be inside the repository because the tools resolve their
  # configuration — tsconfig, .rubocop.yml, the gitleaks allowlist — from it.
  # They are also registered with `git add -N`, because the gates scope
  # themselves to tracked files: CI always lints a checked-out commit, so an
  # untracked probe would be quietly skipped and prove nothing.
  def with_probe(path, contents)
    full = File.join(PIPELINE_ROOT, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
    run("git", "add", "--intent-to-add", path)
    yield full
  ensure
    run("git", "rm", "--cached", "--force", "--quiet", path)
    FileUtils.rm_f(full)
    directory = File.dirname(full)
    FileUtils.rmdir(directory) if Dir.exist?(directory) && Dir.empty?(directory)
  end

  describe "the job list" do
    it "names every job the Story requires, and each is scheduled by a workflow" do
      required = %w[static unit integration contract security-fast frontend e2e-critical migrations]

      expect(PIPELINE.names).to include(*required)

      scheduled = Dir.glob(File.join(PIPELINE_ROOT, ".github/workflows/*.yml"))
                     .map { |path| File.read(path) }.join

      required.each do |job|
        expect(scheduled).to include("- #{job}\n"),
          "#{job} is defined but no workflow schedules it"
      end
    end

    it "reports every job individually rather than as one pass or fail" do
      output, status = run("bin/ci-job", "frontend")

      expect(status).to be_success
      # The job's name, and the check's name inside it, each with a result.
      expect(output).to match(/components\s+PASS/)
      expect(output).to match(/ci-job:frontend: PASS/)
    end

    it "gives each check a name, a result, a duration and — when red — a reason" do
      Dir.mktmpdir do |directory|
        destination = File.join(directory, "frontend.json")
        run("bin/ci-job", "frontend", "--out", destination)
        report = JSON.parse(File.read(destination))

        expect(report["gate"]).to eq("ci-job:frontend")
        expect(report["result"]).to eq("pass")
        expect(report["checks"].first.keys)
          .to include("check", "result", "duration_ms", "reason")
      end
    end

    # The defect this replaces: the command loop was fed by a here-string, the
    # here-string could not be materialised, the body never ran — and the job
    # reported `ci-job:static: PASS` with zero checks and exit 0. A gate that
    # certifies an execution which did not happen is worse than no gate.
    it "refuses to report a result for checks it did not run" do
      script = <<~SH
        set -uo pipefail
        cd "#{PIPELINE_ROOT}"
        source bin/_gate_lib.sh
        gate_begin "probe" "text"
        gate_run "ran" true
        # Two results the run believes in and never wrote — what an interrupted
        # loop leaves behind.
        GATE_EXPECTED_CHECKS=3
        gate_finish
      SH

      output, status = Open3.capture2e("bash", "-c", script, chdir: PIPELINE_ROOT)

      expect(status).not_to be_success, "an interrupted gate must not report PASS"
      expect(output).to include("recorded 1 of 3")
    end

    it "records one result per declared command, so a short run is visible" do
      Dir.mktmpdir do |directory|
        destination = File.join(directory, "frontend.json")
        run("bin/ci-job", "frontend", "--out", destination)
        report = JSON.parse(File.read(destination))

        expect(report["checks"].length).to eq(PIPELINE.job("frontend").commands.length)
      end
    end

    # A slot with no commands must not claim to have tested anything. A false
    # green is worse than a missing check, because nobody goes looking for it.
    it "reports an unpopulated slot as empty, never as passing" do
      output, status = run("bin/ci-job", "load-smoke")

      expect(status).to be_success
      expect(output).to include("EMPTY")
      expect(output).to include("populated by M13-04")
      expect(output).not_to include("PASS")
    end

    # Found the hard way: `spec/policies` and `spec/contracts` were declared
    # suite types with no directory, and RSpec does not run zero specs — it
    # raises LoadError, so the `contract` and `integration` jobs died on a
    # missing folder rather than on anything about the code.
    it "gives every declared suite type somewhere to live" do
      require_relative "../../lib/gates/suite_types"

      Opanel::Gates::SuiteTypes::TYPES.each do |type, paths|
        paths.each do |path|
          expect(Dir.exist?(File.join(PIPELINE_ROOT, path))).to be(true),
            "#{path} is declared as the home of `#{type}` specs but does not exist; " \
            "RSpec raises LoadError rather than running nothing"
        end
      end
    end

    it "keeps the nightly and release-candidate slots declared and empty" do
      (PIPELINE.stage_jobs("nightly") + PIPELINE.stage_jobs("rc")).each do |job|
        expect(job.commands).to be_empty, "#{job.name} is no longer a slot — update this spec"
        expect(job.populated_by.to_s).not_to be_empty,
          "#{job.name} is empty but does not say which Milestone fills it"
      end
    end
  end

  # AC 2–6: one per failure class, each proved to block.
  describe "a red check blocks" do
    it "blocks a typecheck error" do
      probe = "app/frontend/ci-probe/broken.ts"

      with_probe(probe, "export const broken: number = \"not a number\"\n") do
        output, status = run("bin/typecheck")

        expect(status).not_to be_success, "a type error must fail the static job"
        expect(output).to include("ci-probe/broken.ts")
      end
    end

    it "blocks a lint error" do
      probe = "lib/opanel/ci_probe_broken.rb"

      with_probe(probe, <<~RUBY) do
        # frozen_string_literal: true
        def broken
          x = 1
            y = 2
          x+y
        end
      RUBY
        output, status = run("bin/lint")

        expect(status).not_to be_success, "a lint offence must fail the static job"
        expect(output).to include("ci_probe_broken.rb")
      end
    end

    it "blocks a failing test" do
      probe = "spec/unit/ci_probe_failing_spec.rb"

      with_probe(probe, <<~RUBY) do
        require "spec_helper"

        RSpec.describe "a deliberately failing example" do
          it "fails" do
            expect(1).to eq(2)
          end
        end
      RUBY
        _output, status = run("bin/test", probe)

        expect(status).not_to be_success, "a red test must fail its job"
      end
    end

    it "blocks a detected secret" do
      skip "gitleaks is not installed" unless system("command -v gitleaks > /dev/null 2>&1")

      # Assembled from fragments so this spec file does not itself hold a string
      # the scanner recognises — and deterministic, because a randomly generated
      # value crosses the entropy threshold only sometimes, and a flaky security
      # test is a defect (Annex D §20.1).
      #
      # Not AWS's published example key and not under tmp/: both are allowlisted
      # on purpose, so a probe using either would prove only that the allowlist
      # works. This is a GitHub PAT shape, in a path a real leak could occupy.
      token = "ghp_" + ("qJ7fLx2mBv9NcRt4WgYh6ZdKpS3aEuXo" + "1n5T")

      with_probe("config/ci/.ci-probe.env", "GITHUB_TOKEN=#{token}\n") do
        output, status = run("bin/security", "--fast")

        expect(status).not_to be_success, "a secret in the tree must fail security-fast"
        # The report names the file and the rule. It never prints the value:
        # a scanner that echoes what it found publishes it into the CI log.
        expect(output).not_to include(token)
      end
    end

    it "blocks an invalid migration" do
      probe = "db/migrate/29990101000000_ci_probe_invalid.rb"

      with_probe(probe, <<~RUBY) do
        class CiProbeInvalid < ActiveRecord::Migration[8.1]
          def up
            remove_column :infrastructure_checkpoints, :name
          end
        end
      RUBY
        output, status = run("bin/migration-gate")

        expect(status).not_to be_success, "an invalid migration must fail the migrations job"
        expect(output).to include("ci_probe_invalid")
      end
    end
  end

  describe "the Merge Gate" do
    def merge_gate(*arguments)
      output, status = run("bin/merge-gate", "--format", "json", *arguments)
      [ JSON.parse(output), status ]
    end

    # Annex I §15.2, item by item. The list is the gate: an item that is not
    # checked is an item nobody is enforcing.
    it "requires every item of the §15.2 checklist" do
      report, _status = merge_gate("--base", "main")

      expect(report["checks"].map { |check| check["name"] }).to contain_exactly(
        "base-branch-current", "ci-green", "critical-zero", "high-zero",
        "migration-rollout-safe", "rollback-known", "story-status-consistent",
        "documentation-current", "pipeline-change-authorised", "required-approvals"
      )
    end

    # Not "a majority is green" and not "nothing is red": each required job,
    # present and passing. Otherwise deleting the failing job unblocks the merge.
    it "requires CI green by job name, so a job that did not run is not a job that passed" do
      Dir.mktmpdir do |directory|
        report, status = merge_gate("--base", "main", "--results", directory)
        ci_green = report["checks"].find { |check| check["name"] == "ci-green" }

        expect(status).not_to be_success
        expect(ci_green["result"]).to eq("fail")
        PIPELINE.required_for_merge.each do |job|
          expect(ci_green["reason"]).to include(job)
        end
      end
    end

    it "fails when a required job reported red" do
      Dir.mktmpdir do |directory|
        PIPELINE.required_for_merge.each do |job|
          result = job == "integration" ? "fail" : "pass"
          File.write(File.join(directory, "#{job}.json"), JSON.generate(gate: job, result: result))
        end

        report, _status = merge_gate("--base", "main", "--results", directory)
        ci_green = report["checks"].find { |check| check["name"] == "ci-green" }

        expect(ci_green["result"]).to eq("fail")
        expect(ci_green["reason"]).to include("integration (fail)")
      end
    end

    # What cannot be verified is not assumed satisfied. Required approvals live
    # in branch protection; without the evidence the gate says so and blocks.
    it "fails closed on a control it cannot verify" do
      report, _status = merge_gate("--base", "main")
      approvals = report["checks"].find { |check| check["name"] == "required-approvals" }

      expect(approvals["result"]).to eq("fail")
    end

    # M00-R17. The two checks whose whole job is to block a merge on Critical and
    # High looked for `tmp/security/report.json` and `review/*.json`. The pipeline
    # writes `security-report.json` and the reviews are Markdown, so both found
    # nothing, counted zero, and passed on every branch — including the ones with
    # findings.
    describe "the sources it reads for Critical and High" do
      def severity_check(report, severity) =
        report["checks"].find { |check| check["name"] == "#{severity}-zero" }

      def with_repository(files)
        Dir.mktmpdir do |root|
          files.each do |path, content|
            full = File.join(root, path)
            FileUtils.mkdir_p(File.dirname(full))
            File.write(full, content)
          end

          report, status = merge_gate("--base", "main", "--root", root)
          yield report, status
        end
      end

      let(:clean_report) do
        JSON.generate(report: "security", counts: { "critical" => 0, "high" => 0 }, findings: [])
      end

      it "reads the report path the pipeline actually writes" do
        jobs = YAML.safe_load_file(File.join(PIPELINE_ROOT, "config/ci/jobs.yml"))
        written = jobs.dig("jobs", "security-fast", "commands").map(&:last)
          .find { |command| command.include?("--out") }[/--out\s+(\S+)/, 1]

        expect(File.read(File.join(PIPELINE_ROOT, "bin/merge-gate"))).to include(written)
      end

      it "blocks when the scan never ran, rather than counting zero" do
        with_repository({}) do |report, status|
          expect(status).not_to be_success
          expect(severity_check(report, "critical")["reason"])
            .to include("a scan nobody ran is not a scan that found nothing")
        end
      end

      it "blocks on a report it cannot parse" do
        with_repository("tmp/security/security-report.json" => "{ not json") do |report, _status|
          expect(severity_check(report, "high")["reason"]).to include("not readable JSON")
        end
      end

      it "blocks on a report that predates the per-vulnerability format" do
        old = JSON.generate(report: "security",
          findings: [ { scanner: "npm-audit", severity: "blocking" } ])

        with_repository("tmp/security/security-report.json" => old) do |report, _status|
          expect(severity_check(report, "high")["reason"]).to include("records no high count")
        end
      end

      it "counts a High the scan found" do
        found = JSON.generate(report: "security", counts: { "critical" => 0, "high" => 2 })

        with_repository("tmp/security/security-report.json" => found) do |report, _status|
          expect(severity_check(report, "high")["reason"]).to include("2 in the security scan")
          expect(severity_check(report, "critical")["result"]).to eq("pass")
        end
      end

      # The reviews are Markdown. Reading them is the difference between "no
      # blocking finding" and "no file this glob matched".
      it "counts a blocking finding in a Markdown review of a done Story" do
        review = <<~MARKDOWN
          # Review — M99-01

          ### F-1 — the executor is reachable from a controller

          - **Severidade:** Critical
          - **Estado:** open
        MARKDOWN

        with_repository(
          "tmp/security/security-report.json" => clean_report,
          "docs/implementation/M99/tasks.json" =>
            JSON.generate(stories: [ { "id" => "M99-01", "status" => "done", "commit" => "abc" } ]),
          "docs/implementation/M99/review/M99-01.md" => review
        ) do |report, status|
          expect(status).not_to be_success
          expect(severity_check(report, "critical")["reason"])
            .to include("1 unresolved in M99/review/M99-01")
        end
      end

      it "passes when the same review records the finding as resolved" do
        review = <<~MARKDOWN
          # Review — M99-01

          ### F-1 — the executor is reachable from a controller

          - **Severidade:** Critical
          - **Estado:** resolved
        MARKDOWN

        with_repository(
          "tmp/security/security-report.json" => clean_report,
          "docs/implementation/M99/tasks.json" =>
            JSON.generate(stories: [ { "id" => "M99-01", "status" => "done", "commit" => "abc" } ]),
          "docs/implementation/M99/review/M99-01.md" => review
        ) do |report, _status|
          expect(severity_check(report, "critical")["result"]).to eq("pass")
        end
      end
    end
  end

  # AC11. A gate that any Story may quietly edit is not a gate.
  describe "a change to the pipeline" do
    it "is refused unless a commit names the Story or ADR that authorises it" do
      source = File.read(File.join(PIPELINE_ROOT, "bin/merge-gate"))

      expect(source).to include("PIPELINE_PATHS")
      expect(source).to match(%r{\.github/workflows/})
      expect(source).to match(%r{config/ci/})
      expect(source).to match(%r{lib/gates/})
    end

    it "is owned, so GitHub also demands a human review of it" do
      codeowners = File.read(File.join(PIPELINE_ROOT, ".github/CODEOWNERS"))

      %w[/.github/ /config/ci/ /lib/gates/ /bin/merge-gate].each do |path|
        expect(codeowners).to include(path)
      end
    end
  end

  describe "evidence" do
    it "is archived per run, by job, and redacted before it is uploaded" do
      archive = YAML.safe_load_file(File.join(PIPELINE_ROOT, ".github/actions/archive/action.yml"))
      steps = archive.dig("runs", "steps")

      redact = steps.find { |step| step["run"].to_s.include?("bin/redact-artifacts") }
      upload = steps.find { |step| step["uses"].to_s.include?("upload-artifact") }

      expect(redact).not_to be_nil, "artifacts must be redacted before they are archived"
      expect(steps.index(redact)).to be < steps.index(upload),
        "redaction after the upload protects nothing — the artifact is already published"
      expect(upload.dig("with", "name")).to include("github.run_id")
    end

    it "is uploaded even when the job failed, because a red run is the one worth reading" do
      workflow = YAML.safe_load_file(File.join(PIPELINE_ROOT, ".github/workflows/ci.yml"))

      workflow.fetch("jobs").each_value do |job|
        archive = job.fetch("steps", []).find { |step| step["uses"].to_s.include?("actions/archive") }
        next if archive.nil?

        expect(archive["if"]).to eq("always()")
      end
    end

    # M00-R19. A job name and `result: pass`, on their own, say that something
    # passed and nothing about what: two branches produce indistinguishable files,
    # and a result produced over uncommitted changes looks like one produced over
    # the commit it sits beside.
    it "names the commit, the branch and whether the tree was dirty" do
      Dir.mktmpdir do |directory|
        destination = File.join(directory, "contract.json")
        _output, status = run("bin/ci-job", "contract", "--out", destination)
        result = JSON.parse(File.read(destination))

        expect(status).to be_success
        expect(result["commit"]).to match(/\A[0-9a-f]{40}\z/)
        expect(result["branch"]).not_to be_empty
        expect(result).to have_key("dirty")
        expect(result["finished_at"]).to match(/\A\d{4}-\d{2}-\d{2}T[\d:]+Z\z/)
      end
    end
  end

  describe "the flaky rate" do
    it "reports the rate and the top offenders across archived runs" do
      Dir.mktmpdir do |directory|
        # The same test, twice, with different outcomes — which is the only way
        # flakiness is visible at all, and why one run cannot show it.
        File.write(File.join(directory, "run-1.xml"), <<~XML)
          <testsuite>
            <testcase classname="./spec/unit/example_spec.rb" name="converges"/>
            <testcase classname="./spec/unit/example_spec.rb" name="is stable"/>
          </testsuite>
        XML
        File.write(File.join(directory, "run-2.xml"), <<~XML)
          <testsuite>
            <testcase classname="./spec/unit/example_spec.rb" name="converges">
              <failure message="expected true">boom</failure>
            </testcase>
            <testcase classname="./spec/unit/example_spec.rb" name="is stable"/>
          </testsuite>
        XML

        output, status = run("bin/flaky-rate", "--format", "json", directory)
        report = JSON.parse(output)

        expect(status).to be_success
        expect(report["flaky_tests"]).to eq(1)
        expect(report["flaky_rate_percent"]).to eq(50.0)
        expect(report["top_offenders"].first["id"]).to include("converges")
        expect(report["top_offenders"].first["failure_rate_percent"]).to eq(50.0)
      end
    end

    it "does not retry a failing test to make it green" do
      source = File.read(File.join(PIPELINE_ROOT, "bin/flaky-rate"))

      expect(source).to include("It measures; it does not retry")
      expect(File.read(File.join(PIPELINE_ROOT, ".rspec"))).not_to match(/retry/i)
    end
  end

  describe "the CI environment" do
    # The failure this catches: the setup action read `node-version-file: .nvmrc`
    # and no .nvmrc was ever committed, so every job died in setup before running
    # a single check — and nothing in the repository said so, because a workflow
    # is otherwise only exercised by pushing.
    it "points only at files that exist" do
      Dir.glob(File.join(PIPELINE_ROOT, ".github/{workflows,actions}/**/*.yml")).each do |path|
        contents = File.read(path)
        name = path.delete_prefix("#{PIPELINE_ROOT}/")

        contents.scan(/^\s*[\w-]*version-file:\s*(\S+)/).flatten.each do |referenced|
          expect(File.exist?(File.join(PIPELINE_ROOT, referenced))).to be(true),
            "#{name} reads #{referenced}, which is not in this repository"
        end

        contents.scan(%r{uses:\s*(\./[\w./-]+)}).flatten.each do |referenced|
          expect(File.exist?(File.join(PIPELINE_ROOT, referenced, "action.yml"))).to be(true),
            "#{name} uses #{referenced}, which has no action.yml"
        end
      end
    end

    # One declaration of the Node contract. Two is how CI and a developer machine
    # end up on different majors.
    it "reads the Node version from the file bin/setup reads" do
      declared = JSON.parse(File.read(File.join(PIPELINE_ROOT, "package.json"))).dig("engines", "node")

      expect(declared).not_to be_nil, "package.json declares no engines.node"
      expect(File.read(File.join(PIPELINE_ROOT, "bin/setup"))).to include("engines", "node")
      expect(File.read(File.join(PIPELINE_ROOT, ".github/actions/setup/action.yml")))
        .to include("node-version-file: package.json")
    end

    it "carries no production credential" do
      workflows = Dir.glob(File.join(PIPELINE_ROOT, ".github/workflows/*.yml"))

      workflows.each do |path|
        contents = File.read(path)
        expect(contents).not_to match(/(?:\A|_)(PROD|PRODUCTION)_/i),
          "#{File.basename(path)} names a production variable"
      end
    end

    it "runs the same commands locally as in CI" do
      workflows = Dir.glob(File.join(PIPELINE_ROOT, ".github/workflows/*.yml")).map { |p| File.read(p) }

      # Every job step that runs a suite goes through bin/ci-job. A workflow
      # that inlined `bundle exec rspec` could differ from what anyone can run.
      expect(workflows.join).not_to match(/run: .*bundle exec rspec/)
      expect(workflows.join).not_to match(/run: .*npx vitest/)
    end
  end
end
