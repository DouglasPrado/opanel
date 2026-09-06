require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Tests run against real PostgreSQL, never SQLite (Annex D §5). A schema that has
# drifted from db/schema.rb aborts the run instead of producing a green suite
# against the wrong shape.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort "#{error.message}\nRun `bin/rails db:prepare` before the suite."
end

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.use_transactional_fixtures = true
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]

  # The seed is printed by the progress formatter and recorded here too, so a
  # CI log that scrolled past it still says how to reproduce the run.
  config.before(:suite) { Rails.logger.info(event: "suite.started", seed: RSpec.configuration.seed) }
end
