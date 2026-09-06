# Flaky-test quarantine — Annex D §20.1.
#
# A flaky test is a defect. It is never fixed by retrying until green: that turns
# a real, intermittent bug into a slower pipeline and a suite nobody trusts. What
# it gets instead is a quarantine with an owner and a deadline.
#
#     it "converges after a partial failure", quarantine: {
#       owner: "douglas", until: "2026-10-01", reason: "races with the sweep; see M01-15"
#     } do
#
# The example is skipped until the deadline. **After the deadline it runs again**,
# and if it is still flaky the suite goes red — so a quarantine cannot become a
# permanent way of not looking at something.
#
# Intermittent failures in security, restore or concurrency tests may not be
# quarantined at all: those block release until understood.
module Quarantine
  REQUIRED_KEYS = %i[owner until reason].freeze
  FORBIDDEN_TYPES = %i[security].freeze

  def self.validate!(metadata)
    details = metadata[:quarantine]

    unless details.is_a?(Hash)
      raise ArgumentError, "quarantine: must be a Hash with #{REQUIRED_KEYS.join(', ')}"
    end

    missing = REQUIRED_KEYS - details.keys
    unless missing.empty?
      raise ArgumentError, "quarantine: is missing #{missing.join(', ')} — a quarantine without an " \
                           "owner and a deadline is a permanent skip"
    end

    if FORBIDDEN_TYPES.include?(metadata[:type])
      raise ArgumentError, "a #{metadata[:type]} example may not be quarantined: an intermittent " \
                           "failure there blocks release until it is understood (Annex D §20.1)"
    end

    Date.parse(details[:until].to_s)
  end

  def self.expired?(details)
    Date.parse(details[:until].to_s) < Date.current
  end
end

RSpec.configure do |config|
  config.around(:each, :quarantine) do |example|
    details = example.metadata[:quarantine]
    Quarantine.validate!(example.metadata)

    if Quarantine.expired?(details)
      # The deadline passed: run it. If it is still flaky, that is now visible.
      example.run
    else
      example.skip(
        "quarantined until #{details[:until]} (owner: #{details[:owner]}) — #{details[:reason]}"
      )
    end
  end
end
