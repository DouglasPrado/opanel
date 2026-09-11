# frozen_string_literal: true

require "rails_helper"

RSpec.describe "StalledOperations query", type: :unit do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  it "identifies QUEUED operations with stale next_attempt_at" do
    # Healthy QUEUED operation
    healthy = create(:operation, :queued, team: team, resource_id: service.id, next_attempt_at: 1.minute.from_now)

    # Stale QUEUED operation (next_attempt_at in the past)
    stale = create(:operation, :queued, team: team, resource_id: service.id, next_attempt_at: 5.minutes.ago)

    query = StalledOperations.new
    results = query.call

    expect(results.pluck(:id)).to include(stale.id)
    expect(results.pluck(:id)).not_to include(healthy.id)
  end

  it "identifies RUNNING operations without a recent heartbeat" do
    heartbeat_threshold = 10.minutes.ago

    # Healthy RUNNING operation (recent attempt)
    healthy = create(:operation, :running, team: team, resource_id: service.id, updated_at: 2.minutes.ago)

    # Stale RUNNING operation (old last attempt)
    stale = create(:operation, :running, team: team, resource_id: service.id, updated_at: 15.minutes.ago)

    query = StalledOperations.new(heartbeat_threshold: heartbeat_threshold)
    results = query.call

    expect(results.pluck(:id)).to include(stale.id)
    expect(results.pluck(:id)).not_to include(healthy.id)
  end

  it "excludes terminal operations" do
    create(:operation, :succeeded, team: team, resource_id: service.id, next_attempt_at: 5.minutes.ago)
    create(:operation, :failed, team: team, resource_id: service.id, next_attempt_at: 5.minutes.ago)
    create(:operation, :superseded, team: team, resource_id: service.id, next_attempt_at: 5.minutes.ago)

    query = StalledOperations.new
    results = query.call

    expect(results).to be_empty
  end

  it "respects batch size limit" do
    10.times do |i|
      create(:operation, :queued, team: team, resource_id: service.id, next_attempt_at: (10 - i).minutes.ago)
    end

    query = StalledOperations.new(batch_size: 3)
    results = query.call

    expect(results.count).to eq(3)
  end

  it "excludes operations already stalled (stalled_at is set)" do
    stalled_op = create(:operation, :queued, team: team, resource_id: service.id,
                                    next_attempt_at: 10.minutes.ago, stalled_at: 5.minutes.ago)
    fresh_stale = create(:operation, :queued, team: team, resource_id: service.id,
                                   next_attempt_at: 10.minutes.ago, stalled_at: nil)

    query = StalledOperations.new
    results = query.call

    expect(results.pluck(:id)).to include(fresh_stale.id)
    expect(results.pluck(:id)).not_to include(stalled_op.id)
  end
end
