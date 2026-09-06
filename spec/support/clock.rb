# Clock control.
#
# Expiry, retry backoff, lease renewal and retention are all time-dependent, and a
# test that waits for real time is a test nobody runs. Freezing and travelling
# makes those behaviours checkable in milliseconds and, more importantly,
# deterministically — a sleep-based test fails on a slow machine for a reason that
# has nothing to do with the code.
#
# Used from M00-03's retry ceiling onward; leases and fencing tokens in M01-16 and
# secret-version retention in M03 depend on it.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers

  # A frozen clock must not leak into the next example.
  config.after { travel_back }
end
