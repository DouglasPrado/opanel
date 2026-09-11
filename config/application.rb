require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Configuration is validated before the application class exists.
#
# Missing or malformed configuration has to stop the boot, not surface on the
# first request that happens to need the key — a process that starts with a key
# missing is a process running on whatever default was lying around, which is the
# opposite of "secure by default" (Annex I §2).
#
# Required directly rather than autoloaded: Zeitwerk is not set up this early, and
# this check has to run before anything else can depend on the configuration.
require_relative "../lib/opanel/configuration"
Opanel::Configuration.validate_or_abort!(environment: ENV.fetch("RAILS_ENV", "development"))

# The log formatter is installed while the application class is being defined,
# which is also before Zeitwerk. Required for the same reason as the
# configuration above, and excluded from autoloading so it is not loaded twice.
require_relative "../lib/opanel/redaction"
require_relative "../lib/opanel/log_formatter"
require_relative "../lib/opanel/correlation_middleware"

# The identifier registry of ADR-0002, validated on every boot in every
# environment. A duplicate type prefix makes an identifier ambiguous in a log, an
# audit record, an API response and a Swarm label at once, so it has to be a boot
# error rather than something discovered on the one route that happens to use the
# colliding type. Required directly, and excluded from autoloading below, for the
# same reason as the configuration above.
require_relative "../lib/opanel/identifier"
Opanel::Identifier.validate_registry!

module Opanel
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    #
    # lib/gates/ holds the quality-gate checkers. They are required directly by
    # the bin/ scripts and by their specs so they run without booting Rails —
    # the Pre-commit Gate has to afford them on every commit — which means
    # Zeitwerk must not also manage them.
    config.autoload_lib(
      ignore: %w[assets tasks gates rubocop
                 opanel/configuration.rb opanel/redaction.rb opanel/log_formatter.rb
                 opanel/correlation_middleware.rb opanel/identifier.rb]
    )

    # app/frontend/ holds the React/TypeScript tree bundled by Vite. Rails treats
    # every app/* directory as an autoload path, so Zeitwerk has to be told to
    # stay out of it explicitly.
    Rails.autoloaders.main.ignore(Rails.root.join("app/frontend"))

    # One JSON object per line, with the correlation fields already attached and
    # redaction applied at the sink. Configured for every environment: a log that
    # is only structured in production is a format nobody has actually read.
    config.log_formatter = Opanel::LogFormatter.new

    # Rails' own request id becomes the correlation id at the HTTP edge, so the
    # value a user can quote, the value in the log and the value carried into the
    # job that request enqueues are one value (doc 09 §19).
    #
    # After ActionDispatch::RequestId, which generates the id — and which already
    # sits after the Executor, so CurrentAttributes have been reset by the time
    # this runs. Rails::Rack::Logger comes next, so "Started GET" is already
    # correlated.
    config.middleware.insert_after ActionDispatch::RequestId, Opanel::CorrelationMiddleware

    # Unhandled failures render an Inertia page carrying the request id instead of
    # Rails' static HTML, so a user can quote an id that exists in the server log
    # and no internal detail reaches the browser (doc 09 §28, Annex C §17).
    config.exceptions_app = ->(env) { ErrorsController.action(:show).call(env) }

    # Solid Queue in every environment, including development and test. An
    # in-process adapter would let a job pass locally and then fail against a real
    # queue — exactly the class of defect the queue is supposed to surface.
    #
    # The queue lives in the primary database. It is still not a source of truth:
    # PostgreSQL holds the Operation, and the recovery sweep of M01-15 re-enqueues
    # what the broker loses. Sharing the database removes an operational moving
    # part; separating it later is a schema change, not a design change.
    config.active_job.queue_adapter = :solid_queue

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
