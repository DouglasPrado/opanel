# The CI environment is the test environment with eager loading forced on and its
# own database. Keeping it separate means an autoload or constant-resolution error
# fails a named CI job instead of hiding behind development's lazy loading, and
# CI never shares a database with a developer's local test run.
require_relative "test"

Rails.application.configure do
  config.eager_load = true

  # Deprecations are failures in CI: a warning nobody reads is a warning that
  # becomes a breaking upgrade later.
  config.active_support.deprecation = :raise
end
