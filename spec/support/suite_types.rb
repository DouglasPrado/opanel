require_relative "../../lib/gates/suite_types"

# The Rails-native types come from `infer_spec_type_from_file_location!`; these are
# Opanel's own directories. Declaring them from the same map `bin/test --type`
# reads means the two cannot drift apart.
RSpec.configure do |config|
  {
    unit: %w[unit architecture gates documentation frontend],
    integration: %w[integration],
    contract: %w[contracts],
    security: %w[security]
  }.each do |type, directories|
    directories.each do |directory|
      config.define_derived_metadata(file_path: %r{/spec/#{directory}/}) do |metadata|
        metadata[:type] ||= type
      end
    end
  end
end
