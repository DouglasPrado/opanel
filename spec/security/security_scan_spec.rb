require "rails_helper"
require "open3"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require Rails.root.join("lib/gates/dependency_gate")
require Rails.root.join("lib/gates/secret_allowlist")
require Rails.root.join("lib/gates/security_report")
require Rails.root.join("lib/gates/security_waivers")

# A scanner nobody proved can fail is a scanner that reports "clean" forever.
# Each one is planted with a finding it must catch, and the waiver policy is
# tested at its two boundaries: a waiver without an owner and an expiry is not a
# waiver, and an expired one blocks again.
RSpec.describe "security scanning", type: :security do
  def run(*command, env: {})
    Open3.capture2e(env, *command, chdir: Rails.root.to_s)
  end

  describe "secret scan" do
    # Planted in a temporary file inside the repository, scanned, then removed.
    # A fixture committed to disk would be a secret in the repository, which is
    # the thing being prevented.
    def scan_with_planted(content)
      # Outside the repository on purpose: tmp/ is allowlisted by the scan
      # configuration, so a fixture placed there would prove nothing.
      #
      # And deliberately one level *under* a directory named tmp/ inside that
      # scratch space. The allowlist entry used to read `tmp/.*`, unanchored,
      # which silenced the scan for every path containing `tmp/` anywhere —
      # including /tmp, where Dir.mktmpdir lands on Linux. These examples passed
      # here, where macOS puts a scratch directory under /var/folders, and
      # reported `scanned ~0 bytes (0) — no leaks found` on the CI runner. Planting
      # under a tmp/ gives the fixture the same shape on every platform, so an
      # un-anchored entry fails this everywhere instead of only where it is run.
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "tmp"))
        File.write(File.join(directory, "tmp", "planted.txt"), content)

        output, status = run(
          "gitleaks", "dir", directory,
          "--config", Rails.root.join("config/security/gitleaks.toml").to_s,
          "--redact", "--no-banner", "--exit-code", "1"
        )

        yield output, status
      end
    end

    # Deterministic, and assembled from fragments so no whole credential-shaped
    # literal sits in this file for the repository's own scan to trip over.
    #
    # Deterministic matters: an earlier version generated these randomly and was
    # intermittently green, because gitleaks applies an entropy threshold and a
    # random string sometimes falls below it. A flaky security test is a defect
    # (docs/engineering/flaky-tests.md), not something to retry.
    let(:planted_aws_key) { [ "AKIA", "QYLPMN5H", "HHFPZAM2" ].join }
    let(:planted_github_token) { [ "ghp_", "A1b2C3d4E5f6G7h8", "I9j0K1l2M3n4O5p6Q7r8" ].join }
    let(:planted_private_key) do
      body = Array.new(6) { SecureRandom.base64(48) }.join("\n")
      "-----BEGIN RSA PRIVATE KEY-----\n#{body}\n-----END RSA PRIVATE KEY-----\n"
    end

    it "detects a planted AWS access key" do
      scan_with_planted("AWS_ACCESS_KEY_ID=#{planted_aws_key}\n") do |output, status|
        expect(status).not_to be_success, "the secret scan did not detect a planted key:\n#{output}"
      end
    end

    it "detects a planted GitHub token" do
      scan_with_planted("github_token = \"#{planted_github_token}\"\n") do |_output, status|
        expect(status).not_to be_success
      end
    end

    it "detects a planted private key" do
      scan_with_planted(planted_private_key) do |_output, status|
        expect(status).not_to be_success
      end
    end

    it "does not print the secret it found" do
      scan_with_planted("AWS_ACCESS_KEY_ID=#{planted_aws_key}\n") do |output, _status|
        expect(output).not_to include(planted_aws_key),
          "the report must name the file, the line and the rule — never the value (Annex C §21.1)"
      end
    end

    it "leaves a file with nothing sensitive alone" do
      scan_with_planted("service converged 3/3 tasks\nrevision 12 applied\n") do |_output, status|
        expect(status).to be_success, "a scanner that flags ordinary text gets ignored, and then protects nothing"
      end
    end

    # A Story Report and its evidence are exactly where a credential ends up by
    # accident: someone pastes the output of a command that printed one. The
    # scan has to reach those directories, and tmp/ being allowlisted must not
    # quietly extend to them.
    # Held under RepositoryLock: this plants a real, tracked-tree secret and
    # scans the whole tree in the same breath. Under `bin/test --parallel`,
    # another worker's "passes on this repository" full-tree scan
    # (spec/gates/gate_scripts_spec.rb, spec/gates/ci_pipeline_spec.rb use
    # the same lock around their own probes) would otherwise see this file
    # mid-flight and fail on a leak it never planted.
    it "reaches the report and evidence directories" do
      planted = "docs/implementation/M00/reports/.scan-probe.md"
      full = Rails.root.join(planted)

      Opanel::Gates::RepositoryLock.exclusive do
        begin
          File.write(full, "recovered token: #{planted_github_token}\n")
          output, status = run(
            "gitleaks", "dir", ".",
            "--config", Rails.root.join("config/security/gitleaks.toml").to_s,
            "--redact", "--no-banner", "--exit-code", "1"
          )

          expect(status).not_to be_success,
            "a credential pasted into a Story Report was not detected:\n#{output}"
          expect(output).not_to include(planted_github_token)
        ensure
          FileUtils.rm_f(full)
        end
      end
    end

    # M01-91 §3: the local gate scans the diff, not the tree. The scope has to
    # be provable in both directions — a secret in a changed file is found, and
    # the narrowing is exactly the changed set and nothing looser. Under the
    # same lock as the other planted scans: a parallel worker's full-tree scan
    # must not see this file mid-flight.
    it "finds a secret in a file changed since the merge base under --diff" do
      planted = "docs/implementation/M00/reports/.diff-probe.md"
      full = Rails.root.join(planted)

      Opanel::Gates::RepositoryLock.exclusive do
        begin
          File.write(full, "recovered token: #{planted_github_token}\n")
          output, status = run("bin/security", "--fast", "--diff")

          expect(status).not_to be_success,
            "a credential in a changed file was not detected by --diff:\n#{output}"
          expect(output).not_to include(planted_github_token)
          expect(output).to include("secret-scan-diff")
        ensure
          FileUtils.rm_f(full)
        end
      end
    end

    it "is not allowlisted away from the pack" do
      allowlist = Rails.root.join("config/security/gitleaks.toml").read

      %w[docs/implementation reports evidence].each do |fragment|
        expect(allowlist).not_to include(fragment),
          "#{fragment} is allowlisted, so a credential in a report would not be found"
      end
    end

    # Held under RepositoryLock (see the comment on "reaches the report and
    # evidence directories" above): a full-tree-and-history scan of the real
    # working tree must not overlap with another worker mid-way through
    # staging a synthetic secret of its own — the exact collision that made
    # this example flaky under `bin/test --parallel` (M01-91).
    it "passes on this repository, tree and history" do
      output, status = Opanel::Gates::RepositoryLock.exclusive do
        run("bin/security", "--fast", "--history")
      end

      expect(status).to be_success, output
    end
  end

  describe "dependency scanning" do
    it "runs bundler-audit, npm audit and Brakeman" do
      source = Rails.root.join("bin/security").read

      expect(source).to include("bundle-audit")
      expect(source).to include("npm audit")
      expect(source).to include("brakeman")
    end

    it "blocks a known-vulnerable gem, proven against a controlled advisory" do
      # bundler-audit reads a Gemfile.lock; a lockfile naming a version with a
      # published advisory must be refused.
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "Gemfile"), "source 'https://rubygems.org'\ngem 'rack'\n")
        File.write(File.join(directory, "Gemfile.lock"), <<~LOCK)
          GEM
            remote: https://rubygems.org/
            specs:
              rack (2.0.1)

          PLATFORMS
            ruby

          DEPENDENCIES
            rack

          BUNDLED WITH
             2.5.0
        LOCK

        # The repository's bundle resolves the tool; the temp directory supplies
        # the lockfile it reads from the working directory.
        output, status = Open3.capture2e(
          { "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s },
          "bundle", "exec", "bundle-audit", "check", "--update",
          chdir: directory
        )

        expect(status).not_to be_success, "a known-vulnerable rack was accepted:\n#{output}"
        expect(output).to match(/Advisory|CVE|Vulnerabilities found/i)
      end
    end

    it "sets an explicit npm audit level rather than failing on any severity" do
      expect(Rails.root.join("bin/security").read).to include("--audit-level=high")
    end
  end

  describe "the allowlist" do
    let(:config) { Rails.root.join("config/security/gitleaks.toml").read }

    # M00-10 AC4. This used to count `#` characters in the file, which a single
    # paragraph at the top satisfies for any number of entries — and the way an
    # entry gets added is by pasting it under a comment that was about something
    # else.
    it "explains every entry, checked one entry at a time" do
      violations = Opanel::Gates::SecretAllowlist.check(Rails.root.to_s)

      expect(violations.map(&:message)).to be_empty
    end

    it "refuses an entry with no reason above it" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "config/security"))
        File.write(File.join(directory, "config/security/gitleaks.toml"), <<~TOML)
          [allowlist]
          paths = [
            # Lockfiles are public by construction.
            '''package-lock\\.json''',

            '''app/vault/.*''',
          ]
        TOML

        violations = Opanel::Gates::SecretAllowlist.check(directory)

        expect(violations.map(&:entry)).to eq([ "app/vault/.*" ])
        expect(violations.first.message).to include("carries no reason")
      end
    end

    it "is a check bin/security runs, not a spec nobody wires up" do
      expect(Rails.root.join("bin/security").read).to include("lib/gates/secret_allowlist.rb")
    end

    it "allowlists fixture values rather than whole security spec files" do
      expect(config).not_to match(%r{'''spec/security/}),
        "allowlisting spec/security wholesale would hide a real secret that ended up there"
      expect(config).to include("AKIAIOSFODNN7EXAMPLE")
    end
  end

  describe "waivers" do
    def waiver(**overrides)
      {
        "id" => "npm-audit-2026-001", "tool" => "npm-audit", "finding" => "GHSA-xxxx",
        "risk" => "prototype pollution", "owner" => "douglas",
        "justification" => "build-time only", "mitigation" => "pinned",
        "expires_at" => (Date.today + 30).to_s
      }.merge(overrides)
    end

    it "accepts a complete waiver" do
      expect { Opanel::Gates::SecurityWaivers.build(waiver) }.not_to raise_error
    end

    %w[id tool finding risk owner justification mitigation expires_at].each do |field|
      it "refuses a waiver with no #{field}" do
        expect { Opanel::Gates::SecurityWaivers.build(waiver(field => "")) }
          .to raise_error(Opanel::Gates::SecurityWaivers::InvalidWaiver, /#{field}/)
      end
    end

    it "refuses a waiver with no expiry, which would be a permanent silence" do
      expect { Opanel::Gates::SecurityWaivers.build(waiver("expires_at" => "")) }
        .to raise_error(Opanel::Gates::SecurityWaivers::InvalidWaiver, /permanent silence/)
    end

    it "refuses to let an agent waive the secret scan without recorded human approval" do
      expect {
        Opanel::Gates::SecurityWaivers.build(waiver("tool" => "secret-scan", "id" => "secret-1"))
      }.to raise_error(Opanel::Gates::SecurityWaivers::InvalidWaiver, /human approval/)
    end

    it "accepts a secret-scan waiver that records who approved it" do
      expect {
        Opanel::Gates::SecurityWaivers.build(
          waiver("tool" => "secret-scan", "id" => "secret-1", "approved_by" => "douglas")
        )
      }.not_to raise_error
    end

    describe "expiry, on a controlled clock" do
      let(:waivers) do
        Opanel::Gates::SecurityWaivers.new(
          [ Opanel::Gates::SecurityWaivers.build(waiver("expires_at" => "2026-10-01")) ]
        )
      end

      it "silences the finding while it is in date" do
        travel_to(Time.zone.parse("2026-09-30")) do
          expect(waivers.waives?("npm-audit", "GHSA-xxxx")).to be(true)
          expect(waivers.expired).to be_empty
        end
      end

      it "blocks again the day after it expires" do
        travel_to(Time.zone.parse("2026-10-02")) do
          expect(waivers.waives?("npm-audit", "GHSA-xxxx")).to be(false)
          expect(waivers.expired.map(&:id)).to eq([ "npm-audit-2026-001" ])
        end
      end

      it "warns before it expires, so renewal is deliberate" do
        travel_to(Time.zone.parse("2026-09-25")) do
          expect(waivers.expiring_soon.map(&:id)).to eq([ "npm-audit-2026-001" ])
        end
      end
    end

    it "fails bin/security-waivers --check when one has expired" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "config/security"))
        File.write(File.join(directory, "config/security/waivers.yml"), {
          "waivers" => [ waiver("expires_at" => (Date.today - 1).to_s) ]
        }.to_yaml)

        loaded = Opanel::Gates::SecurityWaivers.load(File.join(directory, "config/security/waivers.yml"))

        expect(loaded.expired).not_to be_empty
      end
    end

    it "has none in this repository — every finding is fixed or blocking" do
      output, status = run("bin/security-waivers", "--check")

      expect(status).to be_success, output
    end
  end

  # M00-10 AC7. The gate was documented as a checklist and never executed; what
  # stood in for it was the spec below asserting that ten hand-written names
  # appeared somewhere in the reports. A hand-written list does not notice the
  # eleventh dependency, which is the one the gate exists for.
  describe "the Dependency Gate" do
    def dependency_violations(files)
      Dir.mktmpdir do |directory|
        files.each do |path, content|
          full = File.join(directory, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, content)
        end

        Opanel::Gates::DependencyGate.check(root: directory)
      end
    end

    it "is documented with the questions Annex I §10.1 requires" do
      template = Rails.root.join("docs/templates/DEPENDENCY_JUSTIFICATION.md").read

      %w[Necessidade Alternativa Manutenção Escopo Licença Segurança Lockfile].each do |criterion|
        expect(template).to include(criterion)
      end
    end

    it "runs, and is green on this repository" do
      output, status = run("ruby", "bin/dependency-gate")

      expect(status).to be_success, output
    end

    it "refuses a dependency no Story Report or ADR justifies" do
      violations = dependency_violations(
        "Gemfile" => %(source "https://rubygems.org"\ngem "some_convenient_gem"\n),
        "Gemfile.lock" => "    some_convenient_gem (1.0.0)\n"
      )

      expect(violations.map(&:name)).to include("some_convenient_gem")
      expect(violations.map(&:message).join).to match(/no Story Report or ADR justifies it/)
    end

    it "accepts one the Story Report explains" do
      violations = dependency_violations(
        "Gemfile" => %(source "https://rubygems.org"\ngem "some_convenient_gem"\n),
        "Gemfile.lock" => "    some_convenient_gem (1.0.0)\n",
        "docs/implementation/M99/reports/M99-01.md" =>
          "## Dependências novas\n\n`some_convenient_gem` — solves X; alternatives evaluated; " \
          "MIT; pinned in `Gemfile.lock`.\n"
      )

      expect(violations).to be_empty
    end

    it "refuses an npm package that is declared but not pinned in the lockfile" do
      violations = dependency_violations(
        "package.json" => JSON.generate("dependencies" => { "some-package" => "^1.0.0" }),
        "package-lock.json" => JSON.generate("packages" => {}),
        "docs/implementation/M99/reports/M99-01.md" =>
          "## Dependências novas\n\n`some-package` — solves X; MIT; pinned in `package-lock.json`.\n"
      )

      expect(violations.map(&:message).join).to match(/is not pinned in package-lock\.json/)
    end

    # M00-R09. The gate asked `corpus.include?(name)` — a substring search over
    # every report and ADR in the repository. Any occurrence answered for the
    # dependency, so a name that appeared for an unrelated reason justified it.
    describe "what counts as a justification" do
      let(:manifest) { %(source "https://rubygems.org"\ngem "redis"\n) }
      let(:lockfile) { "    redis (5.4.0)\n" }

      it "rejects the name appearing in prose about something else" do
        violations = dependency_violations(
          "Gemfile" => manifest,
          "Gemfile.lock" => lockfile,
          "docs/implementation/M99/reports/M99-01.md" =>
            "## Decisões locais\n\nSC-02 resolved the queue to Solid Queue rather than redis.\n"
        )

        expect(violations.map(&:message).join).to match(/no Story Report or ADR justifies it/)
      end

      it "rejects a name inside a dependency section that says nothing about it" do
        violations = dependency_violations(
          "Gemfile" => manifest,
          "Gemfile.lock" => lockfile,
          "docs/implementation/M99/reports/M99-01.md" =>
            "## Dependências novas\n\n`none`. The cache layer will not use redis.\n"
        )

        expect(violations.map(&:message).join).to match(/no Story Report or ADR justifies it/)
      end

      it "rejects a template block whose fields are empty" do
        violations = dependency_violations(
          "Gemfile" => manifest,
          "Gemfile.lock" => lockfile,
          "docs/implementation/M99/reports/M99-01.md" => <<~MARKDOWN
            ## Dependências novas

            ### Dependency: `redis` `5.4.0`

            - **Story:** `M99-01`
            - **Ecosystem:** rubygems
          MARKDOWN
        )

        expect(violations.map(&:message).join)
          .to match(/answers neither|answers no|does not answer/)
      end

      it "accepts a completed template block" do
        violations = dependency_violations(
          "Gemfile" => manifest,
          "Gemfile.lock" => lockfile,
          "docs/implementation/M99/reports/M99-01.md" => <<~MARKDOWN
            ## Dependências novas

            ### Dependency: `redis` `5.4.0`

            - **Story:** `M99-01`
            - **Problema resolvido:** the shared rate-limit counter.
            - **Alternativas avaliadas:** a PostgreSQL table.
            - **Maintenance:** actively maintained.
            - **Security:** no known advisory.
            - **License:** MIT — compatible.
            - **Lockfile:** `Gemfile.lock` — pinned at `5.4.0`.
          MARKDOWN
        )

        expect(violations).to be_empty
      end
    end

    # `lockfile.include?(name)` is a substring test. Every name below appears in
    # the lockfile and none of them is pinned.
    describe "what counts as pinned" do
      it "rejects a gem whose name is only a prefix of another gem's" do
        violations = dependency_violations(
          "Gemfile" => %(source "https://rubygems.org"\ngem "rack"\n),
          "Gemfile.lock" => "GEM\n  specs:\n    rack-test (2.2.0)\n",
          "docs/implementation/M99/reports/M99-01.md" =>
            "## Dependências novas\n\n`rack` — solves X; MIT; pinned in `Gemfile.lock`.\n"
        )

        expect(violations.map(&:message).join).to match(/`rack` is declared but is not pinned/)
      end

      it "rejects an npm package that only appears inside another package's path" do
        violations = dependency_violations(
          "package.json" => JSON.generate("dependencies" => { "debug" => "^4.0.0" }),
          "package-lock.json" =>
            JSON.generate("packages" => { "node_modules/vite/node_modules/debug-fork" => {} }),
          "docs/implementation/M99/reports/M99-01.md" =>
            "## Dependências novas\n\n`debug` — solves X; MIT; pinned in `package-lock.json`.\n"
        )

        expect(violations.map(&:message).join).to match(/`debug` is declared but is not pinned/)
      end

      it "accepts a gem pinned under specs" do
        violations = dependency_violations(
          "Gemfile" => %(source "https://rubygems.org"\ngem "rack"\n),
          "Gemfile.lock" => "GEM\n  specs:\n    rack (3.1.8)\n    rack-test (2.2.0)\n",
          "docs/implementation/M99/reports/M99-01.md" =>
            "## Dependências novas\n\n`rack` — solves X; MIT; pinned in `Gemfile.lock`.\n"
        )

        expect(violations).to be_empty
      end
    end

    it "runs inside bin/security, so CI executes it on every push" do
      expect(Rails.root.join("bin/security").read).to include("bin/dependency-gate")
    end
  end

  # M00-10 AC8. Annex D §24: scanner and version, findings, severity,
  # disposition. An exit code says a scan happened and nothing about what it
  # covered.
  describe "the Security Report", :slow do
    let(:gate) do
      {
        "gate" => "security", "result" => "fail", "duration_ms" => 1234,
        "checks" => [
          { "check" => "secret-scan", "result" => "pass", "duration_ms" => 200, "reason" => "" },
          { "check" => "npm-audit", "result" => "fail", "duration_ms" => 900, "reason" => "1 high" }
        ]
      }
    end

    let(:report) { Opanel::Gates::SecurityReport.build(gate, Rails.root.to_s) }

    it "records the scanner and its version" do
      expect(report[:tools].map { |tool| tool[:name] })
        .to include("gitleaks", "bundler-audit", "npm", "brakeman")
      expect(report[:tools].map { |tool| tool[:version] }).to all(be_a(String))
    end

    it "records the waivers, so an accepted finding is visible as accepted" do
      expect(report[:waivers].keys).to contain_exactly(:active, :expiring_soon, :expired)
    end

    it "names the commit it describes" do
      expect(report[:commit]).to be_present
    end

    it "is written by the run that produced it, and archived" do
      jobs = YAML.safe_load_file(Rails.root.join("config/ci/jobs.yml"))
      scan = jobs.dig("jobs", "security-fast", "commands").map(&:last)
        .find { |command| command.start_with?("bin/security") }

      expect(scan).to include("--out tmp/security/")
      expect(Rails.root.join(".github/actions/archive/action.yml").read).to include("tmp/security/")
    end

    # M00-R09. The report was built from the gate's check list — one entry per
    # tool, `severity: "blocking"`. A check is not a vulnerability: it cannot
    # name the advisory, the package or the severity, so every consumer asking
    # "how many High?" read zero, including from runs that had found something.
    describe "findings taken from the scanners' own results" do
      def report_for(checks, outputs)
        Dir.mktmpdir do |root|
          directory = File.join(root, Opanel::Gates::SecurityScanners::DIRECTORY)
          FileUtils.mkdir_p(directory)
          outputs.each { |name, body| File.write(File.join(directory, name), JSON.generate(body)) }

          Opanel::Gates::SecurityReport.build(
            { "gate" => "security", "result" => "fail", "duration_ms" => 1, "checks" => checks },
            root
          )
        end
      end

      it "carries one finding per advisory, with the severity bundler-audit assigned" do
        found = report_for(
          [ { "check" => "bundler-audit", "result" => "fail", "reason" => "1 advisory" } ],
          "bundler-audit.json" => {
            "results" => [ {
              "type" => "unpatched_gem",
              "gem" => { "name" => "rack", "version" => "2.0.1" },
              "advisory" => { "cve" => "2020-8184", "criticality" => "High",
                              "title" => "Percent-encoded cookies" }
            } ]
          }
        )[:findings]

        expect(found.length).to eq(1)
        expect(found.first).to include(scanner: "bundler-audit", severity: "high", blocking: true)
        expect(found.first[:subject]).to eq("rack 2.0.1")
        expect(found.first[:id]).to eq("2020-8184")
      end

      it "carries one finding per npm advisory, at the severity npm assigned" do
        found = report_for(
          [ { "check" => "npm-audit", "result" => "fail", "reason" => "1 high" } ],
          "npm-audit.json" => {
            "vulnerabilities" => {
              "tar" => {
                "name" => "tar", "severity" => "high", "range" => "<6.2.1", "fixAvailable" => true,
                "via" => [ { "source" => 1103, "title" => "Arbitrary File Creation",
                             "severity" => "high" } ]
              }
            }
          }
        )[:findings]

        expect(found.map { |entry| entry[:severity] }).to eq([ "high" ])
        expect(found.first[:subject]).to eq("tar <6.2.1")
      end

      it "counts Critical and High, so the Merge Gate has a number to read" do
        report = report_for(
          [ { "check" => "secret-scan", "result" => "fail", "reason" => "1 leak" } ],
          "gitleaks.json" => [ { "RuleID" => "generic-api-key", "File" => "config/x.yml",
                                 "StartLine" => 4, "Description" => "Generic API Key" } ]
        )

        expect(report[:counts]).to eq({ "critical" => 1, "high" => 0 })
        expect(report[:findings].first[:severity]).to eq("critical")
      end

      it "never carries the secret itself — rule, file and line only" do
        found = report_for(
          [ { "check" => "secret-scan", "result" => "fail", "reason" => "1 leak" } ],
          "gitleaks.json" => [ { "RuleID" => "generic-api-key", "File" => "config/x.yml",
                                 "StartLine" => 4, "Description" => "Generic API Key",
                                 "Secret" => "sk-live-abcdefghijklmnop", "Match" => "sk-live-abc" } ]
        )[:findings]

        expect(JSON.generate(found)).not_to include("sk-live")
      end

      # Static analysis is reported and tracked in M00 and blocks from M01. The
      # severity stays the scanner's; the policy is a separate field with its
      # reason attached, rather than a quiet downgrade that would make the report
      # disagree with brakeman.
      it "records a brakeman warning at its own severity, marked non-blocking for M00" do
        found = report_for(
          [ { "check" => "brakeman", "result" => "pass", "reason" => "" } ],
          "brakeman.json" => {
            "warnings" => [ { "warning_type" => "SQL Injection", "message" => "Possible SQL injection",
                              "file" => "app/x.rb", "line" => 3, "confidence" => "High",
                              "check_name" => "SQL" } ]
          }
        )[:findings]

        expect(found.first).to include(severity: "high", blocking: false)
        expect(found.first[:disposition]).to match(/informational in M00/)
      end

      # A scanner that ran and left nothing readable has not reported zero.
      it "treats a missing scanner result as a finding rather than as no findings" do
        found = report_for(
          [ { "check" => "bundler-audit", "result" => "pass", "reason" => "" } ], {}
        )[:findings]

        expect(found.first).to include(severity: "high", blocking: true)
        expect(found.first[:id]).to eq("scanner-output-missing")
      end

      it "carries a red gate check that has no scanner behind it" do
        found = report_for(
          [ { "check" => "dependency-gate", "result" => "fail", "reason" => "2 unjustified" } ], {}
        )[:findings]

        expect(found.first).to include(scanner: "dependency-gate", severity: "high", blocking: true)
      end
    end
  end
end
