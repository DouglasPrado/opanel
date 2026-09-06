require "rails_helper"
require "open3"

# The boot itself, in a real subprocess.
#
# A unit test can show that validation returns problems; only a real boot shows
# that the process actually refuses to start, with which exit code and on which
# stream. That distinction is the whole requirement: an application that logs a
# warning and starts anyway is running on defaults nobody chose.
RSpec.describe "boot with invalid configuration", type: :integration do
  ROOT = Rails.root.to_s

  def boot(environment, overrides = {})
    env = {
      "RAILS_ENV" => environment,
      "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile")
    }.merge(overrides)

    Open3.capture3(env, "bundle", "exec", "ruby", "-e", "require './config/environment'; puts 'BOOTED'",
      chdir: ROOT, unsetenv_others: false)
  end

  # A production boot needs every required key; these are the ones under test.
  def production_env(overrides = {})
    {
      "SECRET_KEY_BASE" => "a" * 64,
      "OPANEL_DATABASE_HOST" => "localhost",
      "OPANEL_DATABASE_NAME" => "opanel_does_not_need_to_exist",
      "OPANEL_DATABASE_USERNAME" => "opanel",
      "OPANEL_DATABASE_PASSWORD" => "not-a-real-password"
    }.merge(overrides)
  end

  describe "a missing required key" do
    it "aborts with a non-zero exit code" do
      _out, _err, status = boot("production", production_env("SECRET_KEY_BASE" => ""))

      expect(status).not_to be_success
      expect(status.exitstatus).to eq(Opanel::Configuration::EXIT_CODE)
    end

    it "names the key and what was expected" do
      _out, err, _status = boot("production", production_env("SECRET_KEY_BASE" => ""))

      expect(err).to include("SECRET_KEY_BASE")
      expect(err).to include("is required in production")
      expect(err).to include("at least 32 characters")
    end

    it "points at the versioned example rather than at a credentials file" do
      _out, err, _status = boot("production", production_env("OPANEL_DATABASE_PASSWORD" => ""))

      expect(err).to include(".env.example")
      expect(err).to match(/reads none from a versioned file/)
    end

    it "is distinguishable in the exit code from any other boot failure" do
      # 78 is EX_CONFIG. A crash would be 1; a Ruby-level exception would be 1.
      _out, _err, status = boot("production", production_env("SECRET_KEY_BASE" => ""))

      expect(status.exitstatus).to eq(78)
      expect(status.exitstatus).not_to eq(1)
    end
  end

  describe "a malformed value" do
    it "aborts and describes the expected format" do
      _out, err, status = boot("production", production_env("OPANEL_DATABASE_PORT" => "not-a-port"))

      expect(status).not_to be_success
      expect(err).to include("OPANEL_DATABASE_PORT is set but has an invalid format")
      expect(err).to include("a non-negative integer")
    end

    it "does not print the value it received" do
      _out, err, _status = boot("production",
        production_env("SECRET_KEY_BASE" => "short-and-secret-hunter2"))

      expect(err).not_to include("hunter2")
      expect(err).to include("SECRET_KEY_BASE")
    end
  end

  describe "an optional key that is absent" do
    it "boots on the safe default" do
      out, err, status = boot("test", "OPANEL_DATABASE_CHECKOUT_TIMEOUT" => "")

      expect(status).to be_success, "stderr was:\n#{err}"
      expect(out).to include("BOOTED")
    end

    it "boots development with nothing set at all" do
      out, _err, status = boot("development")

      expect(status).to be_success
      expect(out).to include("BOOTED")
    end
  end
end
