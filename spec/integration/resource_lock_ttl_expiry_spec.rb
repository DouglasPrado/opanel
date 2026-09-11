require "rails_helper"

RSpec.describe "Resource lock TTL expiry" do
  let(:user) do
    User.create!(email: "test-#{SecureRandom.hex(4)}@example.test",
      display_name: "Test User",
      password_digest: Opanel::PasswordHashing.create("test-password"))
  end

  let(:team) do
    created = nil
    ActiveRecord::Base.transaction do
      u = user
      slug = "team-#{SecureRandom.hex(4)}".downcase.gsub(/[^a-z0-9-]/, "-")
      created = Team.create!(name: "Test Team", slug: slug, owner_user_id: u.id)
      TeamMember.create!(team: created, user: u, role: "OWNER", status: "ACTIVE", joined_at: Time.current)
    end
    created
  end

  let(:scope_key) { "service-#{SecureRandom.hex(4)}" }

  # AC7: The TTL guarantees release even when the worker disappears without calling release.
  # This tests the core scenario: worker dies, lease expires, successor acquires.
  it "allows takeover after lease expiry without explicit release" do
    # Worker 1: acquire, then "die" (no release)
    acq1 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 2  # Short TTL for testing
    )
    expect(acq1).to be_success
    token1 = acq1.value.fencing_token

    # Worker 2: attempt immediate acquisition (should fail)
    acq2_imm = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 2
    )
    expect(acq2_imm).not_to be_success
    expect(acq2_imm.code).to eq("CONFLICT")

    # Wait for lease to expire
    acq1.value.update!(lease_until: Time.current - 1.second)

    # Worker 2: acquire again (should succeed, taking over)
    acq2_after = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 2
    )
    expect(acq2_after).to be_success
    token2 = acq2_after.value.fencing_token

    # Verify monotonicity: fencing token must increment on takeover (AC3)
    expect(token2).to eq(token1 + 1)
    # Note: in a single test process, both acquisitions have the same worker identity.
    # In production, workers would have different identities. What matters for AC7
    # is that the TTL allows takeover, and the token monotonicity proves it was a fresh acquisition.
  end

  # AC5, AC7: Release happens only after operation result is persisted.
  # An orphaned lock (no explicit release) expires via TTL after heartbeat stops.
  it "expires orphaned locks via TTL when heartbeat ceases" do
    # Worker acquires and lets heartbeat expire (simulate by setting lease_until to past)
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 1
    )
    lock = acq.value
    original_owner = lock.owner

    # Simulate heartbeat stop by advancing time (in test, we manually expire)
    lock.update!(lease_until: Time.current - 1.second)

    # Verify the lock is now expired
    expired_locks = ResourceLock.where(team_id: team.id).expired
    expect(expired_locks.pluck(:scope_key)).to include(scope_key)

    # New acquisition should succeed (taking over the expired lock)
    new_acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 1
    )
    expect(new_acq).to be_success
    # Verify takeover by checking that fencing_token incremented (AC3, AC7)
    expect(new_acq.value.fencing_token).to eq(lock.fencing_token + 1)
  end

  # AC7: Multiple locks expire independently
  it "manages multiple expiring locks independently" do
    locks = 3.times.map do |i|
      acq = AcquireResourceLock.call(
        team: team,
        scope_key: "service-#{i}",
        ttl_seconds: 120
      )
      acq.value
    end

    # Expire only lock 1
    locks[1].update!(lease_until: Time.current - 1.second)

    # Verify expiration state
    expired_locks = ResourceLock.where(team_id: team.id).expired.pluck(:scope_key)
    expect(expired_locks).to eq([ "service-1" ])

    # Verify others are still active
    active_locks = ResourceLock.where(team_id: team.id).active.pluck(:scope_key).sort
    expect(active_locks).to eq([ "service-0", "service-2" ])
  end
end
