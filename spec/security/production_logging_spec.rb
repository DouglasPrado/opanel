require "rails_helper"
require "open3"
require "json"

# Redaction is only a control if it is installed on the sink the process actually
# writes to (Annex C §17.1).
#
# The unit spec for the formatter proves the formatter masks. It cannot prove
# that production *uses* it, and that is precisely where this broke: assigning
# `config.logger` in an environment file takes railties down a branch that never
# applies `config.log_formatter`, so the process ran on SimpleFormatter and
# printed a synthetic password in the clear. A test that reaches for
# `Opanel::LogFormatter` directly would have stayed green through all of it.
#
# So this boots production in a real subprocess and reads what came out of it.
RSpec.describe "the production log sink", type: :security do
  # Fake by construction, and allowlisted in config/security/gitleaks.toml as
  # fixtures that exist in order to be detected.
  PLANTED_PASSWORD = "hunter2"
  PLANTED_TOKEN = "tok_abcdef123456"

  # `config.eager_load = true` in production (config/environments/production.rb)
  # makes Zeitwerk require every file under every autoload path — including
  # `lib/opanel/`, where spec/gates/ci_pipeline_spec.rb and
  # spec/gates/gate_scripts_spec.rb briefly plant a deliberately broken probe
  # file to prove the lint check rejects it. Under `bin/test --parallel`
  # those specs run in other worker *processes*, sharing this same checkout:
  # if a probe is on disk at the instant this boots, Zeitwerk autoloads it
  # and raises `Zeitwerk::NameError` on a file that was never meant to define
  # a real constant — a boot failure that has nothing to do with logging.
  #
  # Held under RepositoryLock (exclusive, the same lock
  # spec/security/security_scan_spec.rb takes around its own full-tree scan):
  # this reads the whole tree via eager loading, so it must not overlap a
  # probe being planted, for the same reason a secret scan must not.
  def boot_production(ruby)
    env = {
      "RAILS_ENV" => "production",
      "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s,
      "SECRET_KEY_BASE" => "a" * 64,
      "OPANEL_DATABASE_HOST" => "localhost",
      "OPANEL_DATABASE_NAME" => "opanel_does_not_need_to_exist",
      "OPANEL_DATABASE_USERNAME" => "opanel",
      "OPANEL_DATABASE_PASSWORD" => "not-a-real-password",
      "RAILS_LOG_LEVEL" => "info"
    }

    Opanel::Gates::RepositoryLock.exclusive do
      Open3.capture3(
        env, "bundle", "exec", "ruby", "-e", "require './config/environment'; #{ruby}",
        chdir: Rails.root.to_s, unsetenv_others: false
      )
    end
  end

  def json_lines(output)
    output.lines.filter_map do |raw|
      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end
  end

  describe "a secret in a free-text message" do
    let(:booted) do
      boot_production(%(Rails.logger.info("provider rejected password=#{PLANTED_PASSWORD}")))
    end

    it "boots" do
      _out, err, status = booted

      expect(status).to be_success, "production did not boot:\n#{err}"
    end

    it "does not print the value" do
      out, _err, _status = booted

      expect(out).not_to include(PLANTED_PASSWORD),
        "the effective production logger printed a secret in the clear"
    end

    it "masks it at the sink" do
      out, _err, _status = booted

      expect(out).to include(Opanel::Redaction::MASK)
    end
  end

  describe "a secret in a structured field" do
    let(:booted) do
      boot_production(
        %(Rails.logger.info(event: "provider.auth", access_token: "#{PLANTED_TOKEN}"))
      )
    end

    it "masks the value and keeps the field" do
      out, _err, _status = booted
      entry = json_lines(out).find { |line| line["event"] == "provider.auth" }

      expect(entry).not_to be_nil, "production emitted no structured line:\n#{out}"
      expect(entry["access_token"]).to eq(Opanel::Redaction::MASK)
      expect(out).not_to include(PLANTED_TOKEN)
    end
  end

  describe "the shape of a production line" do
    # M00-15 AC1. Asserted against the running process rather than against the
    # formatter class, because the defect was that the two were different things.
    it "is JSON with the mandatory fields" do
      out, _err, _status = boot_production(%(Rails.logger.info("service converged")))
      entry = json_lines(out).find { |line| line["message"].to_s.include?("service converged") }

      expect(entry).not_to be_nil, "production did not log JSON:\n#{out}"
      expect(entry).to include("timestamp", "level", "source")
      expect(entry["level"]).to eq("info")
    end

    it "carries no bracketed log tag inside the message" do
      out, _err, _status = boot_production(
        %(Current.request_id = "req-probe-1"; Rails.logger.info("tagged?"))
      )
      entry = json_lines(out).find { |line| line["message"].to_s.include?("tagged?") }

      expect(entry).not_to be_nil, "production did not log JSON:\n#{out}"
      expect(entry["message"]).to eq("tagged?")
      expect(entry["request_id"]).to eq("req-probe-1")
    end
  end
end
