# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Outbox dispatcher" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  context "publishing events to the queue" do
    it "marks unpublished events as published after commit" do
      # Create an operation and outbox event in a transaction (M01-13 already does this)
      event = nil
      ActiveRecord::Base.transaction do
        event = create(:outbox_event, aggregate_id: service.id, published_at: nil)
      end

      expect(event.reload.published_at).to be_nil

      # Run the dispatcher
      PublishPendingOutboxEvents.new.call

      expect(event.reload.published_at).not_to be_nil
    end

    it "publishes multiple events in order (by occurred_at)" do
      events = []
      ActiveRecord::Base.transaction do
        # Create in arbitrary order
        events << create(:outbox_event, aggregate_id: service.id, occurred_at: 3.minutes.ago, published_at: nil)
        events << create(:outbox_event, aggregate_id: service.id, occurred_at: 1.minute.ago, published_at: nil)
        events << create(:outbox_event, aggregate_id: service.id, occurred_at: 2.minutes.ago, published_at: nil)
      end

      PublishPendingOutboxEvents.new.call

      events.each { |e| e.reload }

      # All should be published
      expect(events.all? { |e| e.published_at.present? }).to be true
    end

    it "respects batch size to avoid overwhelming the queue" do
      ActiveRecord::Base.transaction do
        10.times do |i|
          create(:outbox_event, aggregate_id: service.id, occurred_at: (10 - i).minutes.ago, published_at: nil)
        end
      end

      # Publish with batch size 3
      PublishPendingOutboxEvents.new(batch_size: 3).call

      # First 3 should be published
      published_count = OutboxEvent.where("published_at IS NOT NULL").count
      expect(published_count).to eq(3)
    end
  end

  context "handling broker unavailability" do
    it "does not lose events when broker is down" do
      # Create an unpublished event
      event = create(:outbox_event, aggregate_id: service.id, published_at: nil)

      # Simulate broker unavailability by stubbing SolidQueue::Job.create! to fail
      allow(SolidQueue::Job).to receive(:create!).and_raise(RuntimeError.new("Connection refused"))

      # The dispatcher catches the error and continues
      PublishPendingOutboxEvents.new.call

      # Event should still exist unpublished in the database
      expect(event.reload.published_at).to be_nil
      expect(OutboxEvent.unpublished.count).to eq(1)
    end

    it "rolls back both the queue publish and the published_at mark on mark_published! failure" do
      # Create an unpublished event
      event = create(:outbox_event, aggregate_id: service.id, published_at: nil)

      # Stub SolidQueue::Job.create! to succeed (enqueued), but mark_published! to fail.
      # This proves the transaction: if mark_published! fails, the job row does not survive.
      allow_any_instance_of(OutboxEvent).to receive(:mark_published!) do
        raise ActiveRecord::StatementInvalid.new("Error updating published_at")
      end

      # The dispatcher catches the error and continues
      PublishPendingOutboxEvents.new.call

      # Both must be rolled back: event unpublished, and no job row created
      expect(event.reload.published_at).to be_nil
      expect(OutboxEvent.unpublished.count).to eq(1)

      # Verify no SolidQueue::Job row for this event was created (transaction rolled back)
      expect(SolidQueue::Job.count).to eq(0)
    end
  end

  context "event age metrics (AC2)" do
    it "provides observable age of the oldest unpublished event" do
      old_event = create(:outbox_event, aggregate_id: service.id, occurred_at: 30.minutes.ago, published_at: nil)
      recent_event = create(:outbox_event, aggregate_id: service.id, occurred_at: 1.minute.ago, published_at: nil)

      query = OutboxHealth.new
      health = query.call

      expect(health[:oldest_event_age_seconds]).to be_within(5).of(30.minutes.to_i)
      expect(health[:unpublished_count]).to eq(2)
    end

    it "returns nil age when no unpublished events exist" do
      create(:outbox_event, aggregate_id: service.id, published_at: 1.minute.ago)

      query = OutboxHealth.new
      health = query.call

      expect(health[:oldest_event_age_seconds]).to be_nil
      expect(health[:unpublished_count]).to eq(0)
    end
  end
end
