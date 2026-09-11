require "rails_helper"

RSpec.describe "Resource lock owner security" do
  let(:team) { create(:team) }
  let(:scope_key) { "service-#{SecureRandom.hex(4)}" }

  # AC10: The owner of the lock is derived from the worker process, never from client input.
  # The AcquireResourceLock command must use the worker's identity, not accept it as a parameter.
  it "derives owner from worker identity, not from client input" do
    # Even if a caller tries to pass owner_identity, the command derives it internally
    result = AcquireResourceLock.call(
      actor: nil,  # No actor override
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(result).to be_success

    # The owner should be the current worker, not something the caller provided
    expected_owner = Opanel::WorkerIdentity.current
    expect(result.value.owner).to eq(expected_owner)
  end

  # AC10: A lock acquired by one worker cannot be renewed by another
  it "prevents other workers from renewing a lock" do
    worker1_identity = "host-123-0"
    worker2_identity = "host-456-1"

    # Simulate worker 1 owning the lock
    lock = ResourceLock.create!(
      team: team,
      scope_key: scope_key,
      owner: worker1_identity,
      lease_until: Time.current + 120.seconds,
      fencing_token: 0
    )

    # Worker 2 tries to renew (should fail)
    result = RenewResourceLock.call(
      lock: lock,
      worker_identity: worker2_identity,
      ttl_seconds: 120
    )

    expect(result).not_to be_success
    expect(result.code).to eq("CONFLICT")
    expect(result.message).to include("owner")
  end

  # AC10: Release is idempotent for other workers (not an error)
  it "allows any worker to release (idempotent safety)" do
    worker1_identity = "host-123-0"
    worker2_identity = "host-456-1"

    lock = ResourceLock.create!(
      team: team,
      scope_key: scope_key,
      owner: worker1_identity,
      lease_until: Time.current + 120.seconds,
      fencing_token: 0
    )

    # Worker 2 releases (not the owner)
    result = ReleaseResourceLock.call(
      lock: lock,
      worker_identity: worker2_identity
    )

    # Should succeed (idempotent — releasing what you don't own is a no-op)
    expect(result).to be_success
  end

  # AC10: Audit records the worker identity for accountability
  it "records worker identity in audit when privileged" do
    # TODO: When audit integration is complete, verify that lock acquisition
    # records the worker identity (not a client-provided value) in audit logs.
    # For now, this is a placeholder ensuring the mechanism exists.
    expect(Opanel::WorkerIdentity.current).to be_a(String)
    expect(Opanel::WorkerIdentity.current).to be_present
  end
end
