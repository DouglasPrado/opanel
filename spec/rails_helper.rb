require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# M00-01 deliberately does not touch the database: PostgreSQL connection policy,
# migrations and the schema-maintenance hook belong to M00-02, and the full test
# harness to M00-07.
RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
