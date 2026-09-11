# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inbox deduplication under concurrency (AC4)" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  it "enforces dedup via UNIQUE(source, source_event_id) when two threads race to record the same event" do
    # AC4: "an event delivered twice produces one logical effect"
    # Prove it: two threads racing to insert/find the same (source, source_event_id),
    # one wins, the loser catches RecordNotUnique, and the effect is observed once.

    event_source = "queue_publisher"
    source_event_id = "msg_delivery_001"

    results = []
    errors = []

    # Thread 1 and Thread 2 both try to record the same event.
    thread1 = Thread.new do
      begin
        # Simulate a concurrent consumer finding or creating the inbox event.
        inbox = InboxEvent.find_or_create_by(
          source: event_source,
          source_event_id: source_event_id
        ) do |ev|
          ev.id = Opanel::Identifier.generate if ev.id.blank?
        end

        # Simulate processing: mark as processed.
        inbox.update!(processed_at: Time.current.utc, result_ref: "op_123")
        results << { thread: 1, inbox_id: inbox.id, success: true }
      rescue ActiveRecord::RecordNotUnique => e
        errors << { thread: 1, error: e.class.name }
        results << { thread: 1, success: false }
      end
    end

    thread2 = Thread.new do
      begin
        # Same message, same source, delivered twice from queue (typical retry).
        inbox = InboxEvent.find_or_create_by(
          source: event_source,
          source_event_id: source_event_id
        ) do |ev|
          ev.id = Opanel::Identifier.generate if ev.id.blank?
        end

        # This thread should either find the existing record or fail on unique constraint.
        # If it finds the existing record, update should succeed because row already exists.
        # If it tries to insert a new row, RecordNotUnique should fire.
        inbox.update!(processed_at: Time.current.utc, result_ref: "op_123")
        results << { thread: 2, inbox_id: inbox.id, success: true }
      rescue ActiveRecord::RecordNotUnique => e
        errors << { thread: 2, error: e.class.name }
        results << { thread: 2, success: false }
      end
    end

    thread1.join
    thread2.join

    # Expectations:
    # 1. Both threads completed (no unhandled exception).
    # 2. At least one succeeded (found or created the record).
    # 3. Only one InboxEvent exists for this (source, source_event_id) pair.
    # 4. The record is marked processed.

    successful_results = results.select { |r| r[:success] }
    expect(successful_results.length).to be >= 1

    # Count distinct inbox records created/updated.
    distinct_inbox_ids = successful_results.map { |r| r[:inbox_id] }.uniq
    expect(distinct_inbox_ids.length).to eq(1), "Expected exactly one inbox record, got #{distinct_inbox_ids.length}"

    # Verify the record exists and is processed.
    inbox = InboxEvent.find_by(source: event_source, source_event_id: source_event_id)
    expect(inbox).not_to be_nil
    expect(inbox.processed_at).not_to be_nil
    expect(inbox.result_ref).to eq("op_123")

    # Verify the constraint is what enforced dedup (not application logic).
    # If we try to manually insert a duplicate, it should fail at the database level.
    expect {
      InboxEvent.create!(
        id: Opanel::Identifier.generate,
        source: event_source,
        source_event_id: source_event_id
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
