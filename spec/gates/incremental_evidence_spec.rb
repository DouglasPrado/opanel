require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../../lib/gates/test_evidence"
require_relative "../../lib/gates/story_scope"
require_relative "../../lib/gates/post_commit"

RSpec.describe "incremental gate evidence" do
  let(:evidence) { Opanel::Gates::TestEvidence }
  let(:scope) { Opanel::Gates::StoryScope }

  def git(root, *args)
    output, error, status = Open3.capture3("git", *args, chdir: root)
    raise error unless status.success?

    output.strip
  end

  def fixture
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "spec/unit"))
      File.write(File.join(root, ".gitignore"), "tmp/\n")
      File.write(File.join(root, "spec/unit/first_spec.rb"), "# first\n")
      File.write(File.join(root, "app.rb"), "puts 1\n")
      git(root, "init", "-q")
      git(root, "config", "user.email", "test@example.invalid")
      git(root, "config", "user.name", "Test")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "first")
      git(root, "branch", "-M", "main")
      yield root
    end
  end

  def record(paths, **changes)
    { "input_identity" => "inputs", "inputs_stable" => true, "context" => "environment",
      "spec_files" => paths, "result" => "pass", "tests" => 2, "failures" => 0,
      "errors" => 0, "skipped" => 0, "fast" => false, "parallel" => false,
      "finished_at" => Time.now.utc.iso8601(6) }.merge(changes.transform_keys(&:to_s))
  end

  def missing(records, paths)
    evidence.uncovered(records, paths, identity: "inputs", context: "environment")
  end

  it "combines partial selections without requiring an unrelated full suite" do
    expect(missing([ record([ "unit" ]), record([ "contract" ]) ], %w[unit contract])).to be_empty
    expect(missing([ record([ "unit" ]) ], %w[unit contract])).to eq([ "contract" ])
  end

  it "retains complete coverage after an unrelated failing probe" do
    expect(missing([ record(%w[unit contract]), record([ "probe" ], result: "fail", failures: 1) ],
%w[unit contract])).to be_empty
  end

  it "invalidates an older pass when a newer run fails a requested file" do
    expect(missing([ record([ "unit" ]), record([ "unit" ], result: "fail", failures: 1) ],
[ "unit" ])).to eq([ "unit" ])
  end

  it "refuses skips, empty runs, different environments, unstable inputs and stale input identities" do
    [ { skipped: 1 }, { tests: 0 }, { context: "other" }, { inputs_stable: false },
      { input_identity: "old" }, { fast: true } ].each do |change|
      expect(missing([ record([ "unit" ], **change) ], [ "unit" ])).to eq([ "unit" ])
    end
  end

  it "archives independent records atomically" do
    fixture do |root|
      %w[one two].each { |name|
 evidence.write(File.join(root, "tmp/test-results/runs/#{name}.json"), record([ name ])) }
      expect(evidence.records(root).flat_map { |entry| entry["spec_files"] }).to contain_exactly("one", "two")
    end
  end

  it "ignores report and task bookkeeping but invalidates changes to Story requirements" do
    fixture do |root|
      before = evidence.identity(root)
      directory = File.join(root, "docs/implementation/M01")
      FileUtils.mkdir_p("#{directory}/reports")
      File.write("#{directory}/reports/M01-01.md", "report")
      File.write("#{directory}/tasks.json", "{}")
      expect(evidence.identity(root)).to eq(before)
      FileUtils.mkdir_p("#{directory}/stories")
      File.write("#{directory}/stories/M01-01-example.md", "new acceptance criterion")
      expect(evidence.identity(root)).not_to eq(before)
    end
  end

  it "matches the committed input identity and notices untracked source, deletions and mode changes" do
    fixture do |root|
      initial = evidence.identity(root)
      expect(initial).to eq(evidence.identity(root, revision: "HEAD"))
      File.write(File.join(root, "new.rb"), "puts 2\n")
      expect(evidence.identity(root)).not_to eq(initial)
      git(root, "add", "-A")
      git(root, "commit", "-qm", "new code")
      expect(evidence.identity(root)).to eq(evidence.identity(root, revision: "HEAD"))
      current = evidence.identity(root)
      File.chmod(0o755, File.join(root, "new.rb"))
      expect(evidence.identity(root)).not_to eq(current)
      File.delete(File.join(root, "new.rb"))
      expect(evidence.identity(root)).not_to eq(current)
    end
  end

  it "fixes the Story base once and includes new, unstaged specs" do
    fixture do |root|
      base = scope.start(root, "M01-02")
      File.write(File.join(root, "spec/unit/second_spec.rb"), "# second\n")
      expect(scope.specs(root, "M01-02")).to eq([ "spec/unit/second_spec.rb" ])
      git(root, "add", "-A")
      git(root, "commit", "-qm", "second")
      expect(scope.start(root, "M01-02")).to eq(base)
      expect(scope.specs(root, "M01-02")).to eq([ "spec/unit/second_spec.rb" ])
      scope.start(root, "M01-03")
      expect(scope.files(root, "M01-03")).to be_empty
    end
  end

  it "refuses an invalid explicit base instead of silently reducing coverage" do
    fixture do |root|
      previous = ENV["OPANEL_GATE_BASE"]
      ENV["OPANEL_GATE_BASE"] = "nonexistent-ref"
      expect { scope.files(root, "M01-01") }.to raise_error(RuntimeError)
    ensure
      ENV["OPANEL_GATE_BASE"] = previous
    end
  end

  it "post-commit accepts related evidence after bookkeeping and rejects subsequent source changes" do
    fixture do |root|
      scope.start(root, "M01-02")
      File.write(File.join(root, "spec/unit/second_spec.rb"), "# second\n")
      entry = record([ "spec/unit/second_spec.rb" ], input_identity: evidence.identity(root), context: evidence.context)
      evidence.write(File.join(root, "tmp/test-results/runs/run.json"), entry)
      FileUtils.mkdir_p(File.join(root, "docs/implementation/M01/reports"))
      File.write(File.join(root, "docs/implementation/M01/reports/M01-02.md"), "report")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "Story plus report")
      expect(Opanel::Gates::PostCommit.tests("M01-02", root)).to be_ok
      File.write(File.join(root, "app.rb"), "puts 3\n")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "changed code")
      expect(Opanel::Gates::PostCommit.tests("M01-02", root)).not_to be_ok
    end
  end
end
