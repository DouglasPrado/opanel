require "rails_helper"
require "English"
require "tmpdir"
# lib/gates is deliberately outside Zeitwerk so the bin/ scripts can load it
# without booting Rails (see config/application.rb).
require Rails.root.join("lib/gates/workspace_guardrail")
require "fileutils"

# No production credential may exist in the autonomous workspace (Annex H §3.2).
#
# The rule is checked by a command rather than trusted, because the point of the
# autonomous loop is that nobody is watching while it runs. Each detection is
# planted and must fire, and a clean workspace must stay clean — a guardrail that
# flags everything is as useless as one that flags nothing.
RSpec.describe Opanel::Gates::WorkspaceGuardrail, type: :security do
  def findings(env: {}, files: {})
    Dir.mktmpdir do |root|
      files.each do |name, content|
        path = File.join(root, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      described_class.new(env: env, root: root).findings
    end
  end

  describe "credential shapes in the environment" do
    {
      "an AWS access key" => { "AWS_ACCESS_KEY_ID" => "AKIAIOSFODNN7EXAMPLE" },
      "a GitHub token" => { "GH_TOKEN" => "ghp_0123456789abcdefghij" },
      "a Stripe live key" => { "PAYMENTS" => "sk_live_0123456789abcdefghij" },
      "a Slack token" => { "SLACK" => "xoxb-1234567890-abcdefghij" },
      "a private key" => { "TLS_KEY" => "-----BEGIN RSA PRIVATE KEY-----\nMIIE" },
      "a JWT" => { "SESSION" => "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NX0.dBjftJeZ4CVPmB92K27u" }
    }.each do |description, env|
      it "detects #{description}" do
        expect(findings(env: env)).not_to be_empty, "#{description} was not detected"
      end
    end
  end

  describe "credential destinations" do
    it "detects a variable that names production and carries a value" do
      result = findings(env: { "PRODUCTION_DATABASE_PASSWORD" => "anything" })

      expect(result.map(&:detail)).to include(a_string_matching(/naming production/))
    end

    it "detects a connection URL with a password pointing off this machine" do
      result = findings(env: { "DATABASE_URL" => "postgres://opanel:pw@db.prod.example.com:5432/app" })

      expect(result.map(&:detail)).to include(a_string_matching(/not this machine/))
    end

    it "detects a Docker host that is not local" do
      result = findings(env: { "DOCKER_HOST" => "tcp://10.0.0.5:2376" })

      expect(result.map(&:detail)).to include(a_string_matching(/not local/))
    end

    it "detects a Rails credentials file, which Opanel does not use" do
      result = findings(files: { "config/master.key" => "0123456789abcdef" })

      expect(result.map(&:source)).to include("config/master.key")
    end

    it "detects a credential in a git-ignored .env" do
      result = findings(files: { ".env" => "AWS_SECRET=AKIAIOSFODNN7EXAMPLE\n" })

      expect(result.map(&:source)).to include("file: .env")
    end
  end

  describe "what it must not flag" do
    it "allows a local connection URL" do
      expect(findings(env: { "DATABASE_URL" => "postgres://opanel:pw@localhost:5432/opanel_development" }))
        .to be_empty
    end

    it "allows a Unix-socket Docker host" do
      expect(findings(env: { "DOCKER_HOST" => "unix:///var/run/docker.sock" })).to be_empty
    end

    it "allows RAILS_ENV=production, which is a mode and not a secret" do
      expect(findings(env: { "RAILS_ENV" => "production" })).to be_empty
    end

    it "does not mistake REPRODUCIBLE_BUILD for a production variable" do
      expect(findings(env: { "REPRODUCIBLE_BUILD" => "1" })).to be_empty
    end

    it "allows an empty variable, however it is named" do
      expect(findings(env: { "PRODUCTION_TOKEN" => "" })).to be_empty
    end

    it "leaves an ordinary development environment alone" do
      expect(findings(env: {
        "RAILS_ENV" => "development",
        "OPANEL_DATABASE_HOST" => "localhost",
        "PATH" => "/usr/bin:/bin"
      })).to be_empty
    end
  end

  describe "reporting" do
    it "names the source and the pattern, never the value" do
      result = findings(env: { "AWS_ACCESS_KEY_ID" => "AKIAIOSFODNN7EXAMPLE" })
      serialized = result.map(&:to_h).to_s

      expect(serialized).to include("AWS_ACCESS_KEY_ID")
      expect(serialized).not_to include("AKIAIOSFODNN7EXAMPLE")
    end

    it "says a leaked credential is compromised, not merely misplaced" do
      result = findings(env: { "AWS_ACCESS_KEY_ID" => "AKIAIOSFODNN7EXAMPLE" })

      expect(result.first.remedy).to match(/rotate/)
    end
  end

  describe "this workspace" do
    it "holds no production credential" do
      output = `#{Rails.root.join('bin/workspace-guardrail')} 2>&1`

      expect($CHILD_STATUS).to be_success, output
    end
  end
end
