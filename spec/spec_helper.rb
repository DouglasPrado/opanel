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
end
