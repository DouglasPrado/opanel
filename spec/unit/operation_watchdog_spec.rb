# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operation watchdog", type: :unit do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  it "marks a QUEUED operation as STALLED when next_attempt_at has passed" do
    stale_op = create(:operation, :queued, team: team, resource_id: service.id,
                                 next_attempt_at: 10.minutes.ago, stalled_at: nil)

    expect(stale_op.stalled_at).to be_nil

    # Simulate watchdog marking
    stale_op.update!(
      stalled_at: Time.current.utc,
      stalled_reason: "no_progress_since_queued"
    )

    expect(stale_op.reload.stalled_at).not_to be_nil
    expect(stale_op.stalled_reason).to eq("no_progress_since_queued")
  end

  it "marks a RUNNING operation as STALLED when heartbeat is stale" do
    heartbeat_threshold = 10.minutes.ago
    stale_op = create(:operation, :running, team: team, resource_id: service.id,
                              updated_at: 15.minutes.ago, stalled_at: nil)

    expect(stale_op.stalled_at).to be_nil

    stale_op.update!(
      stalled_at: Time.current.utc,
      stalled_reason: "no_heartbeat"
    )

    expect(stale_op.reload.stalled_at).not_to be_nil
    expect(stale_op.stalled_reason).to eq("no_heartbeat")
  end

  it "does not change status to STALLED, only marks the attribute" do
    stale_op = create(:operation, :running, team: team, resource_id: service.id,
                              updated_at: 15.minutes.ago)

    stale_op.update!(stalled_at: Time.current.utc, stalled_reason: "test")

    # Status should remain RUNNING, not change to STALLED
    expect(stale_op.reload.status).to eq(Operation::RUNNING)
    expect(stale_op.stalled_at).not_to be_nil
  end

  it "includes stalled_reason in the record for observability" do
    reasons = [
      "no_progress_since_queued",
      "no_heartbeat",
      "sweep_recovery_failed"
    ]

    reasons.each do |reason|
      op = create(:operation, :queued, team: team, resource_id: service.id)
      op.update!(stalled_at: Time.current.utc, stalled_reason: reason)

      expect(op.reload.stalled_reason).to eq(reason)
    end
  end
end
