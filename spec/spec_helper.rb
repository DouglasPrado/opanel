# Framework-agnostic RSpec configuration. Anything that needs Rails booted lives
# in spec/rails_helper.rb. The full harness (FactoryBot, real-PostgreSQL
# isolation, clock control, concurrency barriers, CI reporters) arrives in M00-07.
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "tmp/rspec-examples.txt"
  config.warnings = false

  # A test that depends on execution order is a defect. Random order by default
  # exposes it, and the seed is printed so the failure is reproducible.
  config.order = :random
  Kernel.srand config.seed

  # `:slow` examples shell out to other gates — they run RuboCop, gitleaks and
  # RSpec itself against planted failures, which is the only way to prove a gate
  # can fail, and costs tens of seconds.
  #
  # `bin/test --fast` excludes them so the Pre-commit Gate stays inside its
  # budget (Annex I §12.1: a gate that is expensive gets bypassed, and a
  # bypassed gate protects nothing). **CI always runs them** — the check moves,
  # it is never removed (Annex I §21.2). Nothing else may be tagged `:slow`:
  # a slow test that is merely slow is a test to fix.
  config.filter_run_excluding(:slow) unless ENV["OPANEL_FAST_TESTS"].to_s.empty?

  # JUnit output is opt-in so an interactive run stays quiet. The file name
  # carries the run id and the worker number, so neither two parallel workers nor
  # a nested `bin/test` overwrite each other's report.
  # Plain Ruby: this file is framework-agnostic and loads before Rails.
  unless ENV["OPANEL_JUNIT"].to_s.empty?
    require "rspec_junit_formatter"
    run_id = ENV.fetch("OPANEL_TEST_RUN_ID", "adhoc")
    config.add_formatter(
      "RspecJunitFormatter",
      "tmp/test-results/rspec-#{run_id}#{ENV['TEST_ENV_NUMBER']}.xml"
    )
  end
end
