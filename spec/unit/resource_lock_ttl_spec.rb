require "rails_helper"

RSpec.describe "Resource lock TTL and expiry", type: :unit do
  let(:team) { create(:team) }
  let(:scope_key) { "service-#{SecureRandom.hex(4)}" }

  # AC7: The TTL guarantees release even when the worker disappears.
  # This test verifies the TTL calculation and expiry detection.
  it "calculates lease_until correctly based on TTL" do
    ttl_seconds = 60
    before_acquisition = Time.current

    result = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: ttl_seconds
    )
    expect(result).to be_success

    lock = result.value
    after_acquisition = Time.current

    # lease_until should be approximately now() + ttl_seconds
    expected_min = before_acquisition + ttl_seconds.seconds
    expected_max = after_acquisition + ttl_seconds.seconds

    expect(lock.lease_until).to be_between(expected_min - 1.second, expected_max + 1.second)
  end

  # AC7: A lock is considered expired when lease_until <= now()
  it "detects expiration correctly" do
    result = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(result).to be_success

    lock = result.value
    expect(lock).not_to be_expired  # Uses .expired? scope

    # Manually set lease_until to the past
    lock.update!(lease_until: Time.current - 1.second)
    lock.reload

    # Now it should be expired
    expired_locks = ResourceLock.where(id: lock.id).expired
    expect(expired_locks).to include(lock)
  end

  # AC7: Multiple locks can expire independently
  it "expires locks independently per scope" do
    scope_a = "service-a"
    scope_b = "service-b"

    r_a = AcquireResourceLock.call(team: team, scope_key: scope_a, ttl_seconds: 120)
    r_b = AcquireResourceLock.call(team: team, scope_key: scope_b, ttl_seconds: 120)

    # Expire only scope_a
    r_a.value.update!(lease_until: Time.current - 1.second)

    expired_locks = ResourceLock.where(team_id: team.id).expired
    expect(expired_locks.map(&:scope_key)).to eq([ scope_a ])
    expect(expired_locks).not_to include(r_b.value)
  end

  # AC5: Renewal extends the lease
  it "extends lease_until when renewed" do
    result = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    lock = result.value
    original_lease_until = lock.lease_until

    # Renew the lock
    renew_result = RenewResourceLock.call(
      lock: lock,
      worker_identity: Opanel::WorkerIdentity.current,
      ttl_seconds: 120
    )
    expect(renew_result).to be_success

    lock.reload
    new_lease_until = lock.lease_until

    # Lease should be extended
    expect(new_lease_until).to be > original_lease_until
  end
end
