source "https://rubygems.org"

# Declared so an incompatible interpreter fails at dependency resolution with an
# explicit message instead of degrading to an unsupported combination.
# .ruby-version pins the exact version used for development and CI.
ruby ">= 3.2.0"

# The approved stack pins Rails 8.1.x. Changing it requires an ADR.
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Durable job backend on PostgreSQL (SC-02). The queue is a delivery mechanism;
# PostgreSQL remains the source of truth about an Operation.
gem "solid_queue"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Test runner for unit/integration/request/policy/contract suites (SC-03).
  gem "rspec-rails", "~> 8.0"
end
