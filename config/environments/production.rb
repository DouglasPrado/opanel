require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT, through the structured, redacting formatter.
  #
  # `config.log_formatter` (config/application.rb) is only applied by Rails when
  # Rails builds the logger itself — railties' `initialize_logger` reads
  # `config.logger ||` first and, when this file supplies one, never reaches the
  # branch that installs the formatter. The effective production sink was
  # therefore ActiveSupport's SimpleFormatter: no JSON, and no redaction. A
  # password interpolated into an exception by a driver was printed in the clear.
  #
  # So the formatter is installed on the logger explicitly, and *before* the
  # TaggedLogging wrapper: `TaggedLogging.new` extends whatever formatter it
  # finds, and assigning one afterwards would replace the extended object and
  # take the tagging methods with it.
  config.logger = ActiveSupport::TaggedLogging.new(
    ActiveSupport::Logger.new($stdout).tap { |logger| logger.formatter = config.log_formatter }
  )

  # No `config.log_tags`. The request id is a first-class field of every line the
  # formatter writes, read from `Current`; a tag would also prepend `[<id>] ` to
  # the `message` value inside the JSON, which is the same id in a place no
  # parser looks for it.

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # The Active Job adapter is set once in config/application.rb: every environment
  # runs the same delivery mechanism, so a job that only misbehaves under a real
  # queue cannot pass locally and fail in production.

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
