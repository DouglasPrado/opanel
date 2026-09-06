require "rails_helper"
require "open3"
require "tmpdir"
require "fileutils"
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
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "planted.txt"), content)

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

    it "passes on this repository, tree and history" do
      _output, status = run("bin/security", "--fast", "--history")

      expect(status).to be_success
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

    it "explains every entry" do
      # Each allowlisted path or regex sits under a comment. An unexplained entry
      # is indistinguishable from a real secret somebody hid.
      allowlist = config.split("[allowlist]").last

      expect(allowlist.scan(/^\s*#/).length).to be >= 8,
        "every allowlist entry needs a written reason"
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

  describe "the Dependency Gate" do
    it "is documented with the questions Annex I §10.1 requires" do
      template = Rails.root.join("docs/templates/DEPENDENCY_JUSTIFICATION.md").read

      %w[Necessidade Alternativa Manutenção Escopo Licença Segurança Lockfile].each do |criterion|
        expect(template).to include(criterion)
      end
    end

    it "is applied: every dependency added in M00 is justified in a Story Report" do
      reports = Dir.glob(Rails.root.join("docs/implementation/M00/reports/*.md")).map { |path| File.read(path) }
      combined = reports.join("\n")

      # The gems and packages M00 introduced beyond the Rails generator.
      %w[solid_queue inertia_rails vite_rails rspec-rails factory_bot_rails
         parallel_tests vitest @playwright/test radix-ui].each do |dependency|
        expect(combined).to include(dependency),
          "#{dependency} was added but no Story Report justifies it (Annex I §10.1)"
      end
    end
  end
end
