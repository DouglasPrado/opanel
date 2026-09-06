require "rails_helper"
require "open3"
require "fileutils"
require "tmpdir"
require "json"

# A trace, a screenshot and a video record whatever was on screen and on the wire.
# That is why they are useful and why they cannot be archived unexamined: an
# Authorization header or a revealed secret would be published to CI storage and
# to whoever has the artifact link (Annex C §17.1).
#
# Each pattern is planted and must be caught, and a clean artifact is left
# untouched — so the check is neither vacuous nor indiscriminate.
RSpec.describe "test artifact redaction", type: :security do
  def redact(files)
    Dir.mktmpdir do |directory|
      files.each do |name, content|
        path = File.join(directory, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, content)
      end

      output, status = Open3.capture2e(
        File.expand_path("../../bin/redact-artifacts", __dir__), "--format", "json", directory
      )

      remaining = Dir.glob(File.join(directory, "**", "*")).select { |path| File.file?(path) }
        .to_h { |path| [ path.delete_prefix("#{directory}/"), File.read(path) ] }

      yield JSON.parse(output), status, remaining
    end
  end

  {
    "authorization header" => 'GET /up\nauthorization: Bearer sk_live_abcdef1234567890',
    "session cookie" => "set-cookie: _opanel_session=Zm9vYmFyYmF6cXV4;path=/",
    "password assignment" => 'DATABASE_PASSWORD="hunter2correct"',
    "api token" => '{"api_key":"opk_9f2c8a1b7d3e5f60"}',
    "connection url" => "postgres://opanel:s3cr3tvalue@db:5432/opanel",
    "recovery key" => 'recovery_key: "RK-4f2a-91bd-cc03"'
  }.each do |description, content|
    it "masks a #{description} in a text artifact" do
      redact({ "error-context.md" => content }) do |report, status, remaining|
        expect(status).to be_success, "a clean run should not fail: #{report}"
        expect(report["masked"]).not_to be_empty, "the #{description} was not detected"
        expect(remaining["error-context.md"]).to include("[REDACTED]")
      end
    end
  end

  it "leaves an artifact with nothing sensitive untouched" do
    content = "expect(locator).toBeVisible() failed on /services\nstatus: 200\n"

    redact({ "error-context.md" => content }) do |report, status, remaining|
      expect(status).to be_success
      expect(report["masked"]).to be_empty
      expect(remaining["error-context.md"]).to eq(content)
    end
  end

  it "deletes a binary artifact it cannot mask, and fails the run" do
    # A trace archive: it cannot be rewritten in place, so losing the diagnostic is
    # the safe outcome. Publishing the credential is not recoverable.
    trace = "PK\x03\x04binary\x00\x00header\nauthorization: Bearer sk_live_abcdef1234567890\x00trailer"

    redact({ "trace.zip" => trace }) do |report, status, remaining|
      expect(status).not_to be_success, "an unmaskable leak must fail the run"
      expect(report["deleted"].map { |entry| entry["file"] }.join).to include("trace.zip")
      expect(remaining).not_to have_key("trace.zip")
    end
  end

  it "reports what it scanned so the run has evidence" do
    redact({ "a.md" => "clean", "nested/b.json" => "{}" }) do |report, status, _remaining|
      expect(status).to be_success
      expect(report["check"]).to eq("redact-artifacts")
      expect(report["result"]).to eq("pass")
      expect(report["files_scanned"]).to eq(2)
    end
  end

  it "is wired into the Playwright teardown, so nothing is archived unscanned" do
    teardown = Rails.root.join("e2e/support/global-teardown.ts").read

    expect(teardown).to include("bin/redact-artifacts")
    expect(Rails.root.join("playwright.config.ts").read).to include("globalTeardown")
  end
end
