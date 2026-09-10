require "spec_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

# M01-92 — test evidence is keyed by the tree it ran against, not by the commit.
#
# Run against a fixture repository rather than this one, for the reason M01-91
# gives: proving a gate must not cost a suite, and a fixture can be dirtied,
# committed and amended without touching anything real. `bin/test-metadata` is
# copied in unchanged; it resolves its root from its own location, so the copy
# operates entirely inside the fixture.
RSpec.describe "test evidence keyed by tree", type: :unit do
  # `spec_helper`, not `rails_helper`: nothing here needs the application, and a
  # gate spec that boots Rails to copy one script into a fixture pays two seconds
  # for nothing — which the review pointed out is the whole subject of the Story.
  GATE_ROOT = File.expand_path("../..", __dir__) unless defined?(GATE_ROOT)

  def sh(*command, dir:)
    stdout, stderr, status = Open3.capture3(*command, chdir: dir)
    raise "#{command.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end

  def fixture
    Dir.mktmpdir("opanel-evidence-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "bin"))
      FileUtils.mkdir_p(File.join(dir, "tmp/test-results"))
      FileUtils.cp(File.join(GATE_ROOT, "bin/test-metadata"), File.join(dir, "bin/test-metadata"))
      FileUtils.mkdir_p(File.join(dir, "lib/gates"))
      FileUtils.cp(File.join(GATE_ROOT, "lib/gates/test_evidence.rb"), File.join(dir, "lib/gates/test_evidence.rb"))
      File.write(File.join(dir, "app.rb"), "puts 1\n")

      sh("git", "init", "-q", dir: dir)
      sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A", dir: dir)
      sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "first", dir: dir)

      yield dir
    end
  end

  # `bin/test-metadata <status> <duration> <type> <parallel> <scope> <fast> <paths>`
  def record(dir)
    sh("ruby", "bin/test-metadata", "0", "1", "all", "no", "all", "no", "", dir: dir)
    JSON.parse(File.read(File.join(dir, "tmp/test-results/rspec-metadata.json")))
  end

  def head_tree(dir) = sh("git", "rev-parse", "HEAD^{tree}", dir: dir)

  # M01-93 — the identity that decides whether a run has already been proved.
  # `tree` answers "did this run against what was committed?"; this answers
  # "is this the same code I already ran?", and for that an untracked file has
  # to count, because a new spec nobody has added yet is code the run executes.
  describe "the committable-tree identity (M01-93)" do
    def identity(dir) = sh("ruby", "bin/test-metadata", "--identity", dir: dir)

    it "changes when a tracked file changes" do
      fixture do |dir|
        before = identity(dir)
        File.write(File.join(dir, "app.rb"), "puts 2\n")

        expect(identity(dir)).not_to eq(before)
      end
    end

    it "changes when an untracked file appears — the case `tree` deliberately ignores" do
      fixture do |dir|
        before = identity(dir)
        File.write(File.join(dir, "new_spec.rb"), "it { }\n")

        expect(identity(dir)).not_to eq(before)
        # And the committed-code identity does not move, which is why the two
        # fields exist rather than one.
        expect(record(dir)["tree"]).to eq(head_tree(dir))
      end
    end

    it "does not change when only an ignored file appears" do
      fixture do |dir|
        File.write(File.join(dir, ".gitignore"), "junk/\n")
        sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A", dir: dir)
        sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "ignore", dir: dir)
        before = identity(dir)

        FileUtils.mkdir_p(File.join(dir, "junk"))
        File.write(File.join(dir, "junk/big.log"), "noise\n")

        expect(identity(dir)).to eq(before)
      end
    end

    it "leaves the repository's own index untouched" do
      fixture do |dir|
        staged_before = sh("git", "status", "--porcelain", dir: dir)
        File.write(File.join(dir, "loose.rb"), "x\n")
        identity(dir)

        expect(sh("git", "status", "--porcelain", dir: dir)).to eq("#{staged_before}?? loose.rb".strip)
      end
    end
  end

  it "records a tree id, alongside the commit it already recorded" do
    fixture do |dir|
      metadata = record(dir)

      expect(metadata["tree"]).to match(/\A[0-9a-f]{40}\z/)
      expect(metadata["commit"]).to match(/\A[0-9a-f]{40}\z/)
    end
  end

  it "records HEAD's own tree when the working tree is clean" do
    fixture do |dir|
      expect(record(dir)["tree"]).to eq(head_tree(dir))
    end
  end

  # AC3 — the property that makes this stricter than the commit check, not
  # looser: one changed tracked file, and the evidence no longer matches.
  it "changes when a tracked file changes, before anything is staged" do
    fixture do |dir|
      before = record(dir)["tree"]
      File.write(File.join(dir, "app.rb"), "puts 2\n")

      after = record(dir)["tree"]

      expect(after).not_to eq(before)
      expect(after).not_to eq(head_tree(dir))
    end
  end

  # AC4 — an amend that changes only the message keeps the evidence valid: the
  # tree is identical, which is the whole point. Today's commit-keyed check
  # invalidates it.
  it "keeps matching HEAD's tree across an amend that changes only the message" do
    fixture do |dir|
      recorded = record(dir)["tree"]
      sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--amend", "-m", "renamed", dir: dir)

      expect(head_tree(dir)).to eq(recorded)
    end
  end

  it "keeps matching HEAD's tree across an empty commit" do
    fixture do |dir|
      recorded = record(dir)["tree"]
      sh("git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "empty", dir: dir)

      expect(head_tree(dir)).to eq(recorded)
    end
  end

  # The security requirement: an untracked file is not what gets committed, so
  # it must not be able to make evidence look valid — or invalid.
  it "ignores untracked files" do
    fixture do |dir|
      before = record(dir)["tree"]
      File.write(File.join(dir, "scratch.txt"), "not tracked\n")

      expect(record(dir)["tree"]).to eq(before)
    end
  end

  # The pre-commit record is keyed by `git write-tree` on a fully staged index;
  # the two ids have to agree on the commit's tree, or one run cannot serve both
  # stages. Asserted rather than assumed.
  it "agrees with git write-tree once the change is staged" do
    fixture do |dir|
      File.write(File.join(dir, "app.rb"), "puts 3\n")
      sh("git", "add", "-A", dir: dir)

      expect(record(dir)["tree"]).to eq(sh("git", "write-tree", dir: dir))
    end
  end

  # M01-92 review F-3: a warning recorded as `skip` is indistinguishable in the
  # JSON report from "not applicable". `gate_warn` records its own value, and it
  # never fails the gate — the blocking version of a check lives in the gate that
  # owns it.
  describe "gate_warn" do
    def run_gate(format)
      Dir.mktmpdir("opanel-gate-") do |dir|
        script = "source bin/_gate_lib.sh; gate_begin probe #{format}; " \
                 "gate_warn mapping 'report maps nothing'; gate_finish"
        # `gate_begin` creates its own results file with mktemp; TMPDIR keeps it
        # inside this fixture. The environment is `capture3`'s first positional
        # argument — as a keyword it is silently taken for a spawn option, which
        # is how the first version of this example ran with no environment at all.
        stdout, _stderr, status = Open3.capture3(
          { "TMPDIR" => dir }, "bash", "-c", script, chdir: GATE_ROOT
        )
        [ stdout, status ]
      end
    end

    it "records a distinct result and does not fail the gate" do
      stdout, status = run_gate("json")

      expect(status.success?).to be(true)
      report = JSON.parse(stdout)
      check = report.fetch("checks").find { |entry| entry["check"] == "mapping" }
      expect(check["result"]).to eq("warn")
      expect(check["result"]).not_to eq("skip")
      expect(report["result"]).to eq("pass")
    end

    it "prints WARN, not SKIP, in the text form" do
      stdout, _status = run_gate("text")

      expect(stdout).to match(/mapping\s+WARN\s+report maps nothing/)
      expect(stdout).not_to include("SKIP")
    end
  end

  it "is stable across two runs with no change in between" do
    fixture do |dir|
      expect(record(dir)["tree"]).to eq(record(dir)["tree"])
    end
  end
end
