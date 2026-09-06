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
    config.autoload_lib(ignore: %w[assets tasks gates])

    # app/frontend/ holds the React/TypeScript tree bundled by Vite. Rails treats
    # every app/* directory as an autoload path, so Zeitwerk has to be told to
    # stay out of it explicitly.
    Rails.autoloaders.main.ignore(Rails.root.join("app/frontend"))

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
