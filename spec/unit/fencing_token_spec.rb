require "rails_helper"

RSpec.describe "Fencing token monotonicity", type: :unit do
  let(:team) { create(:team) }
  let(:scope_key) { "service-#{SecureRandom.hex(4)}" }

  # AC3: The fencing token is monotonic per scope.
  it "increments monotonically on each acquisition" do
    # First acquisition: token = 0 (initial)
    result1 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(result1).to be_success
    token1 = result1.value.fencing_token
    expect(token1).to eq(0)

    # Release and acquire again: token = 1
    ReleaseResourceLock.call(lock: result1.value, worker_identity: Opanel::WorkerIdentity.current)

    result2 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(result2).to be_success
    token2 = result2.value.fencing_token
    expect(token2).to eq(1)

    # Acquire after expiry (takeover): token = 2
    result2.value.update!(lease_until: Time.current - 1.second)

    result3 = AcquireResourceLock.call(
      team: team,
      scope_key: scope_key,
      ttl_seconds: 120
    )
    expect(result3).to be_success
    token3 = result3.value.fencing_token
    expect(token3).to eq(2)

    # Verify monotonicity
    expect([ token1, token2, token3 ]).to eq([ 0, 1, 2 ])
  end

  # AC3: All scopes maintain independent monotonic sequences.
  it "maintains independent sequences per scope" do
    scope_a = "service-a"
    scope_b = "service-b"

    r1a = AcquireResourceLock.call(team: team, scope_key: scope_a, ttl_seconds: 120)
    r1b = AcquireResourceLock.call(team: team, scope_key: scope_b, ttl_seconds: 120)
    expect(r1a.value.fencing_token).to eq(0)
    expect(r1b.value.fencing_token).to eq(0)

    ReleaseResourceLock.call(lock: r1a.value, worker_identity: Opanel::WorkerIdentity.current)
    ReleaseResourceLock.call(lock: r1b.value, worker_identity: Opanel::WorkerIdentity.current)

    r2a = AcquireResourceLock.call(team: team, scope_key: scope_a, ttl_seconds: 120)
    r2b = AcquireResourceLock.call(team: team, scope_key: scope_b, ttl_seconds: 120)
    expect(r2a.value.fencing_token).to eq(1)
    expect(r2b.value.fencing_token).to eq(1)
  end
end
