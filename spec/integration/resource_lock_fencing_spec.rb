require "rails_helper"

RSpec.describe "Fencing token prevents stale worker" do
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

  # AC4: A worker with an expired lease cannot persist results (fencing token check).
  # This is the central test of M01-15 (Failure Scenarios table, "Worker atrasado volta").
  it "rejects fenced writes from a worker whose token is stale" do
    # Worker 1: acquire lock, capture token
    acq1 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq1).to be_success
    old_token = acq1.value.fencing_token

    # Simulate worker 1 losing the lock (lease expiry)
    acq1.value.update!(lease_until: Time.current - 1.second)

    # Worker 2: takes over (acquires with incremented token)
    acq2 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq2).to be_success
    new_token = acq2.value.fencing_token
    expect(new_token).to eq(old_token + 1)

    # Worker 1: attempts to persist a result using the old token (STALE)
    # This simulates the scenario where worker 1 comes back from a network outage.
    # The fenced write must refuse the old token.
    operation = create(:operation, team: team, fencing_token: new_token)

    expect {
      operation.update_with_fencing_token(
        fencing_token: old_token,  # Old, stale token
        status: Operation::SUCCEEDED
      )
    }.to raise_error(Operation::InvalidTransition)

    # Verify the operation was not updated
    operation.reload
    expect(operation.status).not_to eq(Operation::SUCCEEDED)
  end

  # AC4, part 2: Verify the correct token allows update (positive case).
  it "allows fenced write with the correct fencing token" do
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq).to be_success

    operation = create(:operation,
      team: team,
      fencing_token: acq.value.fencing_token,
      status: Operation::RUNNING
    )

    # Should not raise
    expect {
      operation.update_with_fencing_token(
        fencing_token: acq.value.fencing_token,
        status: Operation::SUCCEEDED
      )
    }.not_to raise_error

    operation.reload
    expect(operation.status).to eq(Operation::SUCCEEDED)
  end

  # AC4: Even with an active lock, status change without fencing guard raises (C3).
  it "guards against status changes without fencing when lease is active" do
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )

    operation = create(:operation,
      team: team,
      fencing_token: acq.value.fencing_token,
      lease_owner: acq.value.owner,
      lease_until: acq.value.lease_until,
      status: Operation::RUNNING
    )

    # Attempt to update status directly (not through fenced_update)
    # This should raise because the guard flag is not set
    expect {
      operation.update!(status: Operation::SUCCEEDED)
    }.to raise_error(Operation::InvalidTransition)
  end
end
