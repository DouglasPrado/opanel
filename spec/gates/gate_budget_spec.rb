require "spec_helper"

# The budget itself, regression-tested (M01-91 Scope item 4).
#
# `bin/gate local` was 462s, brought down by removing two costs: the suite
# re-entering itself (a spec called `bin/gate`, which called `bin/test`,
# which ran the suite again) and `--parallel` being withheld. Proving the
# live number by calling `bin/gate local` from *inside* this suite would
# reintroduce exactly that recursion — `--changed` would select this very
# file and run it again, which would call `bin/gate local` again, and so
# on. So what runs on every commit is what can run safely: the diagnosis
# logic that turns a report into a named reason, and a static guard against
# the recursion coming back. The live number is measured directly — `bin/gate
# local --story M01-91`, run once, outside the suite — and recorded with its
# per-check timings in the Story Report (Observability Requirements; AC1, AC7).
RSpec.describe "the local gate's budget" do
  BUDGET_ROOT = File.expand_path("../..", __dir__)

  # One number, in one place, with the reason beside it: 462s brought under
  # 90s by removing the suite's own recursion and by using `--parallel`
  # (AC1). A slower machine overrides it explicitly rather than the constant
  # being quietly tuned to one laptop (Failure Scenarios).
  CEILING_MS = Integer(ENV.fetch("OPANEL_GATE_LOCAL_BUDGET_MS", 90_000))

  # Named rather than counted: "the gate is slow" sends the next reader
  # hunting through nine checks; "tests took 118000ms of a 90000ms budget"
  # does not (Observability Requirements, AC7).
  def diagnose(report, ceiling)
    total = report.fetch("duration_ms")
    return nil if total <= ceiling

    slowest = report.fetch("checks").max_by { |check| check["duration_ms"].to_i }
    "#{report.fetch('gate')} took #{total}ms, over its #{ceiling}ms budget — " \
      "#{slowest.fetch('check')} alone took #{slowest.fetch('duration_ms')}ms"
  end

  it "says nothing is wrong when a run is inside the ceiling" do
    within_budget = {
      "gate" => "gate:local", "duration_ms" => 45_000,
      "checks" => [ { "check" => "tests", "duration_ms" => 40_000 } ]
    }

    expect(diagnose(within_budget, CEILING_MS)).to be_nil
  end

  # AC7: the ceiling exceeded produces a named check.
  it "names the check that broke the budget, not just the total" do
    over_budget = {
      "gate" => "gate:local",
      "duration_ms" => 118_452,
      "checks" => [
        { "check" => "format", "duration_ms" => 900 },
        { "check" => "tests", "duration_ms" => 108_000 },
        { "check" => "lint", "duration_ms" => 1_200 }
      ]
    }

    reason = diagnose(over_budget, 90_000)

    expect(reason).to include("tests", "108000ms", "90000ms budget")
  end

  it "picks the single worst offender when more than one check is over its share" do
    over_budget = {
      "gate" => "gate:local",
      "duration_ms" => 95_000,
      "checks" => [
        { "check" => "security", "duration_ms" => 37_000 },
        { "check" => "tests", "duration_ms" => 55_000 }
      ]
    }

    expect(diagnose(over_budget, 90_000)).to include("tests", "55000ms")
  end

  # AC4 / Failure Scenario "a future Story re-introduces recursion": proven
  # statically. Calling `bin/gate local` or `bin/gate pre-commit`
  # unrestricted from inside any spec is exactly what made "tests" run the
  # suite against itself before M01-91 — `--changed` selects the calling
  # spec, which calls the gate again. `--only` is how a spec proves one
  # check without paying for — or re-entering through — the others.
  describe "the suite no longer re-enters itself" do
    # Two call shapes, both seen in this suite: the `gate`/`gate_json` helper
    # (spec/gates/gate_scripts_spec.rb) and a literal `"bin/gate"` argument
    # list (spec/gates/ci_pipeline_spec.rb's `run`). Either one, given
    # `"local"` or `"pre-commit"` with no `--only`, reintroduces the
    # recursion.
    UNRESTRICTED_GATE_CALL = /
      \bgate(?:_json)?\(\s*"(?:local|pre-commit)" |
      "bin\/gate"[^\n]*"(?:local|pre-commit)"
    /x

    it "never calls the full local or pre-commit gate from inside a spec" do
      offenders = Dir.glob(File.join(BUDGET_ROOT, "spec/**/*_spec.rb")).each_with_object([]) do |path, found|
        File.readlines(path).each_with_index do |line, index|
          next unless line =~ UNRESTRICTED_GATE_CALL
          next if line.include?("--only")

          found << "#{path.delete_prefix("#{BUDGET_ROOT}/")}:#{index + 1}"
        end
      end

      expect(offenders).to be_empty,
        "calls the full gate unrestricted, which `--changed` would then select and run again: " \
        "#{offenders.join(', ')}"
    end
  end
end
