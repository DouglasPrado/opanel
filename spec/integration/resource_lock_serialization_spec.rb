require "rails_helper"

RSpec.describe "Resource lock serialization", :concurrent do
  let(:namespace) { unique_namespace("lock") }
  let(:digest) { Opanel::PasswordHashing.create("test-test-test") }

  def user_named(name)
    User.create!(email: "#{namespace}-#{name}@example.test", display_name: name,
      password_digest: digest)
  end

  # Set up Team with OWNER in one atomic transaction
  let(:team) do
    created = nil
    ActiveRecord::Base.transaction do
      # Use a unique identifier per test execution to avoid conflicts in concurrent runs
      unique_id = SecureRandom.hex(4)
      unique_email = "#{namespace}-owner-#{unique_id}@example.test"
      unique_slug = "#{namespace}-#{unique_id}"
      owner = User.create!(email: unique_email, display_name: "Owner",
        password_digest: digest)
      created = Team.create!(name: "Locks #{namespace}", slug: unique_slug,
        owner_user_id: owner.id)
      TeamMember.create!(team: created, user: owner, role: "OWNER", status: "ACTIVE",
        joined_at: Time.current)
    end
    created
  end

  let(:scope_key) { "service-#{namespace}" }

  after(:each) do
    ActiveRecord::Base.transaction do
      ResourceLock.where(team_id: team.id).delete_all if team
      TeamMember.where(team_id: team.id).delete_all if team
      Team.delete(team.id) if team
    end
    User.where("email LIKE ?", "#{namespace}-owner-%").delete_all
  end

  # AC2: Two concurrent mutations on the same scope are serialized.
  # Only one succeeds; the other is blocked until the first releases.
  it "serializes mutations on the same scope with explicit barrier" do
    acquired = []
    barrier = barrier(2)

    concurrently(
      -> {
        barrier.wait  # Both threads wait here

        # Worker 1: acquire lock
        result = AcquireResourceLock.call(
          team: team,
          scope_key: scope_key,
          ttl_seconds: 120
        )
        acquired << [ :worker1, result.success? ]

        if result.success?
          # Hold the lock briefly
          sleep 0.1
          ReleaseResourceLock.call(
            lock: result.value,
            worker_identity: Opanel::WorkerIdentity.current
          )
        end
      },
      -> {
        barrier.wait  # Both threads wait here

        # Worker 2: try to acquire the same lock
        result = AcquireResourceLock.call(
          team: team,
          scope_key: scope_key,
          ttl_seconds: 120
        )
        acquired << [ :worker2, result.success? ]
      }
    )

    # Exactly one worker should have acquired the lock
    successes = acquired.select { |_, success| success }
    expect(successes.length).to eq(1)
  end

  # AC8: Concurrent reads are not blocked by locks on mutations.
  it "allows concurrent reads while mutations are locked" do
    read_results = []
    barrier = barrier(2)

    # First, acquire the lock
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    lock = acq.value

    concurrently(
      -> {
        barrier.wait
        # Worker 1: hold the mutation lock
        sleep 0.15
      },
      -> {
        barrier.wait
        # Worker 2: read while locked (should not block)
        state = ResourceLockState.for(team: team, scope_key: scope_key)
        read_results << state
      }
    )

    expect(read_results.count).to eq(1)
    expect(read_results[0].scope_key).to eq(scope_key)
  end
end
