require "rails_helper"
require "open3"
require "fileutils"
require "tmpdir"
require "json"
require "zlib"

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

  # A real archive, built the way Playwright builds a trace: entries stored with
  # DEFLATE, indexed by a central directory. Written by hand rather than with a
  # gem, because the point is to produce the exact container that defeated the
  # previous check — one whose payload is nowhere in its own bytes.
  def build_zip(entries)
    local = +"".b
    central = +"".b

    entries.each do |name, content|
      data = content.b
      deflated = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
      crc = Zlib.crc32(data)
      offset = local.bytesize

      local << [ 0x04034b50, 20, 0, 8, 0, 0, crc, deflated.bytesize, data.bytesize, name.bytesize, 0 ]
        .pack("VvvvvvVVVvv") << name.b << deflated

      central << [ 0x02014b50, 20, 20, 0, 8, 0, 0, crc, deflated.bytesize, data.bytesize,
                   name.bytesize, 0, 0, 0, 0, 0, offset ].pack("VvvvvvvVVVvvvvvVV") << name.b
    end

    eocd = [ 0x06054b50, 0, 0, entries.length, entries.length,
             central.bytesize, local.bytesize, 0 ].pack("VvvvvVVv")

    local + central + eocd
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

  # The defect this replaces: the scan read the container's bytes and found
  # nothing, because a trace stores its JSON compressed. The archive was reported
  # clean and uploaded with a recoverable credential inside it.
  it "opens a real archive and finds a secret that is only there when decompressed" do
    trace = build_zip(
      "trace.network" => %({"headers":[{"name":"authorization","value":"Bearer sk_live_abcdef1234567890"}]}\n),
      "resources/page.html" => "<html>nothing sensitive</html>"
    )

    expect(trace).not_to include("sk_live_abcdef1234567890"),
      "the fixture is not compressed, so it would not prove anything"

    redact({ "trace.zip" => trace }) do |report, status, remaining|
      expect(status).not_to be_success
      expect(report["deleted"].map { |entry| entry["file"] }.join).to include("trace.zip")
      expect(remaining).not_to have_key("trace.zip")
    end
  end

  it "leaves an archive alone when nothing inside it is sensitive" do
    trace = build_zip(
      "trace.network" => %({"headers":[{"name":"accept","value":"text/html"}]}\n),
      "resources/page.html" => "<html>ordinary output</html>"
    )

    redact({ "trace.zip" => trace }) do |report, status, remaining|
      expect(status).to be_success, "a clean archive must survive: #{report}"
      expect(remaining).to have_key("trace.zip")
    end
  end

  # Not knowing what is inside an artifact is not the same as knowing it is
  # clean. An archive that cannot be opened has been cleared by nobody.
  it "refuses an archive it cannot open" do
    redact({ "trace.zip" => "PK\x03\x04corrupt-and-unreadable".b }) do |report, status, remaining|
      expect(status).not_to be_success
      expect(report["deleted"].map { |entry| entry["patterns"] }.flatten.join)
        .to include("uninspectable-archive")
      expect(remaining).not_to have_key("trace.zip")
    end
  end

  it "refuses a binary format it has no way to inspect" do
    redact({ "diagnostic.bin" => "\x00\x01\x02opaque\x00payload".b }) do |report, status, remaining|
      expect(status).not_to be_success
      expect(report["deleted"].map { |entry| entry["patterns"] }.flatten.join)
        .to include("uninspectable-format")
      expect(remaining).not_to have_key("diagnostic.bin")
    end
  end

  # Screenshots and videos cannot be inspected for text at all. Publishing them
  # is accepted deliberately and the acceptance is written down in the script;
  # what must not happen is the list quietly growing to cover everything.
  it "publishes a screenshot, and still scans its bytes" do
    clean = "\x89PNG\r\n\x1A\n".b + "IDAT ordinary pixels".b
    leaky = "\x89PNG\r\n\x1A\n".b + "tEXtComment\x00authorization: Bearer sk_live_abcdef1234567890".b

    redact({ "shot.png" => clean }) do |_report, status, remaining|
      expect(status).to be_success
      expect(remaining).to have_key("shot.png")
    end

    redact({ "shot.png" => leaky }) do |_report, status, remaining|
      expect(status).not_to be_success
      expect(remaining).not_to have_key("shot.png")
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
