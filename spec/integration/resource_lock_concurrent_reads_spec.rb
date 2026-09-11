require "rails_helper"

RSpec.describe "Resource lock concurrent reads", :concurrent do
  let(:namespace) { unique_namespace("lock") }

  # Set up a Team with its OWNER once, before concurrent tests run
  let(:team) do
    created = nil
    ActiveRecord::Base.transaction do
      digest = Opanel::PasswordHashing.create("test-test-test")
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

  let(:scopes) { 3.times.map { |i| "service-#{i}-#{namespace}" } }

  after(:each) do
    ActiveRecord::Base.transaction do
      ResourceLock.where(team_id: team.id).delete_all if team
      TeamMember.where(team_id: team.id).delete_all if team
      Team.delete(team.id) if team
    end
    User.where("email LIKE ?", "#{namespace}-owner-%").delete_all
  end

  # AC8: Reads are not blocked by locks on mutations.
  # While a worker holds a lock, other processes can read the lock state.
  it "allows concurrent reads while mutations are locked" do
    # Set up three locks
    locks = scopes.map do |scope|
      acq = AcquireResourceLock.call(
        team: team,
        scope_key: scope,
        ttl_seconds: 120
      )
      expect(acq).to be_success
      acq.value
    end

    read_count = 0
    barrier = barrier(2)

    concurrently(
      -> {
        # Worker 1: hold the lock (mutation)
        barrier.wait
        # Keep the lock held briefly
        sleep 0.2
      },
      -> {
        # Worker 2: read while locks are held
        barrier.wait

        # Read all lock states multiple times
        3.times do
          scopes.each do |scope|
            state = ResourceLockState.for(team: team, scope_key: scope)
            expect(state).not_to be_nil
            expect(state.scope_key).to eq(scope)
          end
        end

        read_count += 1
      }
    )

    expect(read_count).to eq(1)
  end

  # AC8: Multiple readers do not interfere with each other
  it "supports multiple concurrent readers" do
    # Acquire lock on one scope
    acq = AcquireResourceLock.call(
      team: team,
      scope_key: scopes[0],
      ttl_seconds: 120
    )
    expect(acq).to be_success

    read_results = []
    barrier = barrier(3)

    concurrently(
      -> {
        # Holder
        barrier.wait
        sleep 0.15
      },
      -> {
        # Reader 1
        barrier.wait
        state = ResourceLockState.for(team: team, scope_key: scopes[0])
        read_results << [ :reader1, state ]
      },
      -> {
        # Reader 2
        barrier.wait
        state = ResourceLockState.for(team: team, scope_key: scopes[0])
        read_results << [ :reader2, state ]
      }
    )

    expect(read_results.count).to eq(2)
    expect(read_results.map { |_, state| state.scope_key }).to all(eq(scopes[0]))
  end

  # AC8: Reads across multiple scopes work simultaneously
  it "reads from multiple scopes without blocking" do
    locks = scopes.map do |scope|
      acq = AcquireResourceLock.call(
        team: team,
        scope_key: scope,
        ttl_seconds: 120
      )
      expect(acq).to be_success
      acq.value
    end

    read_results = []
    barrier = barrier(4)

    concurrently(
      -> {
        # Hold scope 0
        barrier.wait
        sleep 0.15
      },
      -> {
        # Read scope 0 (potentially while held)
        barrier.wait
        s0 = ResourceLockState.for(team: team, scope_key: scopes[0])
        read_results << [ :read_0, s0 ]
      },
      -> {
        # Read scope 1 (independent)
        barrier.wait
        s1 = ResourceLockState.for(team: team, scope_key: scopes[1])
        read_results << [ :read_1, s1 ]
      },
      -> {
        # Read scope 2 (independent)
        barrier.wait
        s2 = ResourceLockState.for(team: team, scope_key: scopes[2])
        read_results << [ :read_2, s2 ]
      }
    )

    expect(read_results.count).to eq(3)
    keys = read_results.map(&:first)
    expect(keys).to include(:read_0, :read_1, :read_2)
  end
end
