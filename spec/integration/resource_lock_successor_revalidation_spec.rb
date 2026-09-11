require "rails_helper"

RSpec.describe "Successor revalidation of actual state" do
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

  # AC6, C2: The successor must revalidate actual state before acting.
  # A worker that takes over after a lease expires must observe the current state
  # and prove it (with a recorded observation) before a fenced write is allowed.
  #
  # The mechanism: AcquireResourceLock returns took_over = true when takeover occurs.
  # The successor must call record_observation! before attempting a fenced write.
  # The fenced write refuses if took_over is true but no observation was recorded.
  it "refuses fenced write on taken-over lease without prior observation" do
    # Worker 1: acquire and let lease expire
    acq1 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    lock1 = acq1.value

    # Expire the lock
    lock1.update!(lease_until: Time.current - 1.second)

    # Worker 2: take over (acquire returns took_over = true)
    acq2 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq2).to be_success
    expect(acq2.value.took_over?).to be(true)

    # Create an operation to update
    operation = create(:operation,
      team: team,
      fencing_token: acq2.value.fencing_token,
      status: Operation::RUNNING
    )

    # Worker 2 attempts fenced write WITHOUT observing first
    # This should fail because took_over is true but no observation was recorded
    expect {
      operation.update_with_fencing_token(
        fencing_token: acq2.value.fencing_token,
        lock: acq2.value,
        status: Operation::SUCCEEDED
      )
    }.to raise_error(Operation::InvalidTransition, /observation/)
  end

  # AC6: Fenced write succeeds after observation is recorded
  it "allows fenced write on taken-over lease after observation is recorded" do
    # Worker 1: acquire and let lease expire
    acq1 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    lock1 = acq1.value
    lock1.update!(lease_until: Time.current - 1.second)

    # Worker 2: take over
    acq2 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq2.value.took_over?).to be(true)

    # Create operation
    operation = create(:operation,
      team: team,
      fencing_token: acq2.value.fencing_token,
      status: Operation::RUNNING
    )

    # Worker 2: record observation on the lock
    acq2.value.record_observation!

    # Now the fenced write should succeed
    expect {
      operation.update_with_fencing_token(
        fencing_token: acq2.value.fencing_token,
        lock: acq2.value,
        status: Operation::SUCCEEDED
      )
    }.not_to raise_error

    operation.reload
    expect(operation.status).to eq(Operation::SUCCEEDED)
  end

  # AC6: Non-takeover cases do not require observation
  it "does not require observation when no takeover occurred" do
    # Fresh acquisition (no takeover)
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(acq.value.took_over?).to be(false)

    operation = create(:operation,
      team: team,
      fencing_token: acq.value.fencing_token,
      status: Operation::RUNNING
    )

    # Should succeed without calling record_observation!
    expect {
      operation.update_with_fencing_token(
        fencing_token: acq.value.fencing_token,
        lock: acq.value,
        status: Operation::SUCCEEDED
      )
    }.not_to raise_error
  end
end
