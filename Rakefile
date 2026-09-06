# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

# parallel:prepare / parallel:create, used by `bin/test --parallel` to give every
# worker its own database.
require "parallel_tests/tasks"
