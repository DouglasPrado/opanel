# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Operation recovery sweep" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  context "recovering lost messages" do
    it "re-enqueues a QUEUED operation whose message was lost (AC3)" do
      # Create a QUEUED operation that should have been picked up by now
      lost_op = create(:operation, :queued, team: team, resource_id: service.id,
                               next_attempt_at: 5.minutes.ago)

      expect(lost_op.status).to eq(Operation::QUEUED)

      # Run the recovery sweep
      RecoverStalledOperations.new.call

      # Operation should be re-enqueued (status may remain QUEUED, but next_attempt_at is reset)
      lost_op.reload
      expect(lost_op.status).to eq(Operation::QUEUED)
      expect(lost_op.next_attempt_at).to be > Time.current.utc
    end

    it "re-enqueues a RUNNING operation with stale heartbeat" do
      running_op = create(:operation, :running, team: team, resource_id: service.id,
                                  updated_at: 15.minutes.ago)

      RecoverStalledOperations.new.call

      running_op.reload
      # After recovery, next_attempt_at should be set to allow re-queuing
      expect(running_op.next_attempt_at).to be > Time.current.utc
    end

    it "does not re-enqueue healthy QUEUED operations" do
      healthy_op = create(:operation, :queued, team: team, resource_id: service.id,
                                  next_attempt_at: 2.minutes.from_now)
      original_attempt_at = healthy_op.next_attempt_at

      RecoverStalledOperations.new.call

      healthy_op.reload
      expect(healthy_op.next_attempt_at).to eq(original_attempt_at)
    end

    it "does not re-enqueue terminal operations" do
      succeeded_op = create(:operation, :succeeded, team: team, resource_id: service.id,
                                     next_attempt_at: 5.minutes.ago)
      failed_op = create(:operation, :failed, team: team, resource_id: service.id,
                                   next_attempt_at: 5.minutes.ago)

      RecoverStalledOperations.new.call

      expect(succeeded_op.reload.status).to eq(Operation::SUCCEEDED)
      expect(failed_op.reload.status).to eq(Operation::FAILED)
    end

    it "never manually changes a FAILED operation's status (AC6)" do
      failed_op = create(:operation, :failed, team: team, resource_id: service.id,
                                  next_attempt_at: 5.minutes.ago)

      RecoverStalledOperations.new.call

      expect(failed_op.reload.status).to eq(Operation::FAILED)
    end
  end

  context "marking stalled operations" do
    it "marks operations as STALLED when threshold is exceeded" do
      stale_queued = create(:operation, :queued, team: team, resource_id: service.id,
                                    next_attempt_at: 10.minutes.ago, stalled_at: nil)

      RecoverStalledOperations.new.call

      stale_queued.reload
      expect(stale_queued.stalled_at).not_to be_nil
      expect(stale_queued.stalled_reason).to eq("no_progress_since_queued")
    end

    it "records the reason for staleness" do
      stale_running = create(:operation, :running, team: team, resource_id: service.id,
                                      updated_at: 15.minutes.ago, stalled_at: nil)

      RecoverStalledOperations.new.call

      stale_running.reload
      expect(stale_running.stalled_reason).to eq("no_heartbeat")
    end
  end
end
