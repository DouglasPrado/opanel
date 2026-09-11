require "spec_helper"
require "json"
require "open3"

# M01-91 — the local gate's budget, asserted so it cannot regress in silence,
# and the recursion that once made it cost a full suite, asserted absent.
#
# ## Why the suite's own duration is read from evidence, not measured here
#
# A spec that ran `bin/gate local` in full would run `bin/test`, which runs this
# spec — the exact re-entry M01-91 exists to remove (AC4). So the cheap checks
# and the diff scan are timed live (`--only`, and `bin/security --fast --diff`
# directly — neither starts rspec), and the suite is judged from the evidence
# its last full run wrote. A ceiling on evidence is still a ceiling: the number
# is in one place, with the reason next to it, and the check that exceeds it
# is named.
#
# ## The numbers, and where they come from
#
# Measured on the reference machine in the session that closed this Story:
# `bin/test --parallel` over 1 735 examples in 297–319 s (10 workers), against
# ~490 s serial; `bin/security --fast --diff` in 18 s against ~80 s for the full
# tree. The Story's original target — the whole gate under 90 s — was measured
# when the suite had ~1 300 examples and parallel ran in 88 s; it grew by a
# third, and a target the suite cannot meet without dropping checks is not a
# target this file may encode. These ceilings are what the measurement supports
# with headroom, and tightening them is a reviewed diff here.
RSpec.describe "the local gate's budget (M01-91)", :slow do
  GATE_ROOT = File.expand_path("../..", __dir__) unless defined?(GATE_ROOT)

  # Milliseconds. Each one is a measurement with headroom, not an aspiration.
  #
  # `contracts` is not here on purpose: it is `bin/test --type contract`, which
  # is the suite runner — the re-entry AC4 forbids — and it rewrites the very
  # evidence the example below reads. The first version listed it and the
  # suite example went pending on evidence this file had just clobbered.
  CEILINGS = {
    "format" => 10_000,
    "lint" => 15_000,
    "typecheck" => 15_000,
    "migrations" => 5_000,
    "fitness" => 5_000
  }.freeze

  # The suite, parallel, with room for a slower machine or a heavier lab run.
  SUITE_CEILING_MS = 420_000
  # The full-tree scan is CI's; the local gate scans the diff — 18 s over the
  # 1 048 files a Milestone branch has changed since its merge base, measured
  # when the scope was written. The first version of this file declared this
  # number and asserted nothing against it (M01-91 review round 4, Medium).
  DIFF_SCAN_CEILING_MS = 60_000

  def gate_json(*arguments)
    output, status = Open3.capture2e("bin/gate", *arguments, "--format", "json", chdir: GATE_ROOT)
    [ JSON.parse(output), status ]
  end

  describe "the cheap checks, timed live" do
    it "each finish under their ceiling, and the report names the one that does not" do
      report, _status = gate_json("local", "--only", CEILINGS.keys.join(","))
      checks = report.fetch("checks")

      over = CEILINGS.filter_map do |name, ceiling|
        entry = checks.find { |c| c["check"] == name }
        next "#{name}: not run" if entry.nil?

        "#{name}: #{entry['duration_ms']}ms > #{ceiling}ms" if entry["duration_ms"].to_i > ceiling
      end

      expect(over).to be_empty, "checks over their budget:\n  #{over.join("\n  ")}"
    end
  end

  # `rspec-metadata-complete.json` is the last *full* run; `bin/test` keeps it
  # beside the last-run record because every partial run — including the
  # `contracts` check `bin/gate local` runs right after the suite — overwrites
  # that one. The first version of this example read the last-run record and
  # went pending after every gate run, which is an assertion that never fires
  # (M01-91 review, Medium). It is pending only on a checkout where the suite
  # has never run in full.
  describe "the diff scan, timed live" do
    it "finishes under its ceiling" do
      output, _status = Open3.capture2e("bin/security", "--fast", "--diff", "--format", "json", chdir: GATE_ROOT)
      scan = JSON.parse(output).fetch("checks").find { |c| c["check"] == "secret-scan-diff" }
      skip "nothing changed since the merge base — no scan to time" if scan.nil? || scan["result"] == "skip"

      expect(scan["duration_ms"].to_i).to be <= DIFF_SCAN_CEILING_MS,
        "secret-scan-diff: #{scan['duration_ms']}ms > #{DIFF_SCAN_CEILING_MS}ms"
    end
  end

  describe "the suite, judged from its evidence" do
    let(:evidence) { File.join(GATE_ROOT, "tmp/test-results/rspec-metadata-complete.json") }

    def git(*arguments) = Open3.capture2(*[ "git", *arguments ], chdir: GATE_ROOT, err: File::NULL).first.strip

    def ancestor?(older, newer)
      system("git", "merge-base", "--is-ancestor", older, newer, chdir: GATE_ROOT, err: File::NULL)
    end

    # The same id bin/test-metadata records: the tracked working tree.
    def working_tree_id
      snapshot = git("stash", "create")
      git("rev-parse", "#{snapshot.empty? ? 'HEAD' : snapshot}^{tree}")
    end

    # Every `done` Story's commit on this line of history, from the packs' own
    # state.
    def closed_story_commits
      Dir.glob(File.join(GATE_ROOT, "docs/implementation/*/tasks.json")).flat_map { |path|
        JSON.parse(File.read(path)).fetch("stories", []).filter_map { |s| s["commit"] if s["status"] == "done" }
      }.select { |c| ancestor?(c, "HEAD") }
    end

    # How many Stories closed after the kept record was written.
    def stories_closed_since(commit)
      closed_story_commits.count { |c| c != commit && ancestor?(commit, c) }
    end

    it "ran under the ceiling the last time it ran in full" do
      skip "no full-suite evidence yet — run bin/test" unless File.exist?(evidence)

      metadata = JSON.parse(File.read(evidence))
      expect(metadata["complete"]).to be(true), "the kept record is not a full-suite run"

      # Provenance and age. A suite cannot read its own duration, so this
      # example is one full run behind by construction; what it may not be is
      # older than the last closed Story. `bin/test` keeps the complete record
      # on every full run, and post-commit refuses to close a Story without a
      # full run at its commit — so the kept record is never older than the
      # newest `done` Story on this line of history, and that is checked here
      # against tasks.json rather than claimed (M01-91 review round 3: ancestry
      # alone bounded nothing). The tree the record was measured on is in the
      # message, next to the working tree, so a reader sees how far behind.
      commit = metadata["commit"].to_s
      skip "the kept record names no commit — run bin/test" unless commit.match?(/\A\h{7,40}\z/)
      unless ancestor?(commit, "HEAD")
        skip "the kept record is from outside this history (#{commit[0, 12]}) — run bin/test"
      end
      # **One** Story behind is allowed, and more is not. A suite cannot read
      # its own duration, so the newest record this example can ever see was
      # written before the Story that is closing — the first version of this
      # bound demanded the record be at or after the last closed Story, and so
      # went pending on exactly the run that closes a Story. `bin/gate
      # post-commit` refuses a suite with a skipped example, so that bound
      # charged every Story an extra full suite. Two Stories behind is drift,
      # and that is what this refuses.
      behind = stories_closed_since(commit)
      if behind > 1
        skip "the kept record (#{commit[0, 12]}) is #{behind} closed Stories behind HEAD — run bin/test"
      end

      provenance = "measured at #{commit[0, 12]}, tree #{metadata['tree'].to_s[0, 12]}; " \
        "working tree #{working_tree_id[0, 12]}"
      expect(metadata["duration_ms"].to_i).to be <= SUITE_CEILING_MS,
        "tests: #{metadata['duration_ms']}ms > #{SUITE_CEILING_MS}ms " \
        "(parallel: #{metadata['parallel']}, #{metadata['tests']} examples; #{provenance})"
    end
  end

  # AC4 — exactly one rspec process per gate run. Proved structurally: no spec
  # anywhere starts the suite, and every gate stage a spec starts is narrowed
  # with --only. A spec that ran a full stage would be the recursion this Story
  # removed, and this is what stops it coming back.
  describe "no re-entry" do
    # Every spec but this one: this file carries the forbidden strings in its
    # own control example, and a guard that reads itself reports the rule for
    # stating the rule. The whole tree, not spec/gates/ — the first rewrite of
    # this guard looked only under spec/gates/ and the review pointed out that
    # a gate call from spec/integration/ would have gone unseen (M01-91 review,
    # High). The version this file replaced scanned spec/**, and so does this.
    SPECS = Dir.glob(File.join(GATE_ROOT, "spec/**/*.rb"))
      .reject { |p| File.basename(p) == "gate_budget_spec.rb" }.freeze

    def code(path) = File.read(path).each_line.reject { |l| l.strip.start_with?("#") }.join

    def relative(path) = path.delete_prefix("#{GATE_ROOT}/")

    # The guards match tokens in the whole text of a spec, not quoted strings
    # on one line: the review of the first fix planted `%w[bin/test --changed]`,
    # `system("bin/test --changed")` and a `("bin/gate",\n "local")` split over
    # two lines, and a guard keyed on `"bin/test"` saw none of them. What these
    # catch is the shapes a spec would naturally use to start a process;
    # deliberate obfuscation (`"bin/" + "test"`) is a review matter, not a
    # regex's.
    #
    # `bin/test` — the runner, not `bin/test-metadata`, and not the words
    # "run bin/test first" in a message — is the token followed by a closing
    # quote or bracket, a flag, an interpolation, or the end of the line. It may
    # appear only as `"bin/test", <argument>` where the argument is not a flag —
    # the one shape the probes use: `run("bin/test", probe)` runs a single
    # planted file to prove the gate fails on it. Every other occurrence —
    # alone, with a flag, inside one string, inside `%w[]`, parked in a
    # variable — is the suite selecting itself.
    SUITE_RUNNER = %r{bin/test(?=["'\]]|\s+(?:--|\#\{)|\s*$)}
    PROBE_CALL = %r{bin/test["']\s*,\s*(?!["']--)\S}

    # A stage that runs `bin/test` — `local` or `pre-commit`; `post-commit`
    # reads evidence and starts nothing — started by the helper
    # (`gate_json("local"`) or by naming the binary, quoted or not, with the
    # stage — or an interpolation, which is a stage the guard cannot read —
    # anywhere in the following whitespace/punctuation. Multi-line argument
    # lists are the reason this is `\s*`, not a line.
    STAGE_CALL = %r{
      \bgate\w*\(\s*["'](?:local|pre-commit)["']
      | bin/gate(?![-\w])["'\]]*[\s,]+["']?(?:local|pre-commit|\#\{)
    }x
    # `expect(File.read(hook)).to include("bin/gate pre-commit")` asserts what a
    # hook says; it starts nothing. An assertion *around* a call
    # (`expect(run("bin/gate", "local"))`) is still a call and is still caught.
    TEXT_ASSERTION = /(?:include|eq|match|start_with|end_with)\(\s*["'][^"'\n]*\z/

    # Comments blanked, not dropped, so a reported line number is the file's.
    def code_lines(path) = File.read(path).each_line.map { |l| l.strip.start_with?("#") ? "\n" : l }.join

    def offenders_in(path, pattern)
      text = code_lines(path)
      text.enum_for(:scan, pattern).filter_map do
        match = Regexp.last_match
        before = text[0, match.begin(0)]
        next if before[/[^\n]*\z/].match?(TEXT_ASSERTION)

        # The call this match starts: up to the paren or bracket that closes it.
        statement = text[match.begin(0), 300][/\A[^)\]]*/]
        next unless yield(statement)

        "#{relative(path)}:#{before.count("\n") + 1}: #{statement.lines.map(&:strip).join(' ')}"
      end
    end

    it "never starts the suite from a spec — only an explicit probe file" do
      offenders = SPECS.flat_map do |path|
        offenders_in(path, SUITE_RUNNER) { |statement| !statement.match?(PROBE_CALL) }
      end

      expect(offenders).to be_empty, "bin/test started without an explicit probe:\n  #{offenders.join("\n  ")}"
    end

    it "narrows every suite-running gate stage it starts with --only" do
      offenders = SPECS.flat_map do |path|
        offenders_in(path, STAGE_CALL) { |statement| !statement.include?("--only") }
      end

      expect(offenders).to be_empty,
        "suite-running gate stages started in full from a spec:\n  #{offenders.join("\n  ")}"
    end

    # The control: the guards recognise what they forbid — including the three
    # shapes that got past the first fix — and accept the one shape allowed.
    it "would recognise a re-entry" do
      re_entries = [
        'run("bin/test", "--changed")', 'run("bin/test")', 'cmd = "bin/test"',
        "Open3.capture2e(*%w[bin/test --changed])", 'system("bin/test --changed")', 'system("bin/test #{flag}")'
      ]
      re_entries.each do |line|
        expect(line).to match(SUITE_RUNNER)
        expect(line).not_to match(PROBE_CALL)
      end
      expect("bin/test-metadata").not_to match(SUITE_RUNNER)
      expect('skip "run bin/test first"').not_to match(SUITE_RUNNER)
      expect("evidence: `bin/test:70`").not_to match(SUITE_RUNNER)
      expect('run("bin/test", probe)').to match(PROBE_CALL)
      expect('run("bin/test", "spec/unit/x_spec.rb")').to match(PROBE_CALL)

      expect('gate_json("local", "--story", "X")').to match(STAGE_CALL)
      expect('run("bin/gate", "pre-commit", "--story", "X")').to match(STAGE_CALL)
      expect("Open3.capture2e(\"bin/gate\",\n  \"local\")").to match(STAGE_CALL)
      expect("system(*%w[bin/gate local])").to match(STAGE_CALL)
      expect('system("bin/gate local")').to match(STAGE_CALL)
      # A stage held in a variable is a stage this guard cannot read, so any
      # interpolation after the binary is treated as one (review round 3).
      expect('system("bin/gate #{stage}")').to match(STAGE_CALL)
      expect('gate_json("post-commit", "--story", "X")').not_to match(STAGE_CALL)
      expect('expect(File.read(hook)).to include("bin/gate pre-commit")'[/\A.*include\(\s*"/]).to match(TEXT_ASSERTION)
      expect('expect(run("bin/gate", "local")).to eq(1)'[/\A.*run\("/]).not_to match(TEXT_ASSERTION)
    end
  end
end
