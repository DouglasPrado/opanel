# frozen_string_literal: true

# The suite types, declared once so `bin/test --type` and the RSpec configuration
# cannot disagree about what a type means.
#
# A type is not decoration: it says what a spec is allowed to touch, and it is the
# unit the CI pipeline schedules. The directory a spec lives in determines its
# type, so a spec cannot become something else by growing.
#
#   unit         one object, no database
#   integration  real PostgreSQL, several objects
#   request      the full Rack stack
#   policy       authorization, proven in both directions
#   contract     an external contract or schema
#   security     a control from Annex C
#
# spec/architecture, spec/gates, spec/documentation and spec/frontend hold checks
# about the repository itself; they need no database and run as `unit`.
#
# Runnable directly so a shell script can ask without booting Rails:
#   ruby lib/gates/suite_types.rb integration
module Opanel
  module Gates
    module SuiteTypes
      TYPES = {
        "unit" => %w[spec/unit spec/architecture spec/gates spec/documentation spec/frontend],
        "integration" => %w[spec/integration],
        "request" => %w[spec/requests],
        "policy" => %w[spec/policies],
        "contract" => %w[spec/contracts],
        "security" => %w[spec/security]
      }.freeze

      def self.paths_for(type)
        TYPES.fetch(type.to_s) do
          raise ArgumentError, "unknown suite type: #{type} (expected one of #{TYPES.keys.join(', ')})"
        end
      end

      def self.all_paths
        TYPES.values.flatten
      end

      def self.names
        TYPES.keys
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts Opanel::Gates::SuiteTypes.paths_for(ARGV.fetch(0))
  rescue ArgumentError, IndexError => error
    warn error.message
    exit 2
  end
end
