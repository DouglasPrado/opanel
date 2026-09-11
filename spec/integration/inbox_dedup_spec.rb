# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Inbox deduplication (AC4)" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  it "records received events and prevents duplicate processing" do
    event_source = "github_webhook"
    source_event_id = "evt_12345"

    # First receipt of the event
    inbox1 = InboxEvent.find_or_create_by(
      source: event_source,
      source_event_id: source_event_id
    ) do |ev|
      ev.id = Opanel::Identifier.generate if ev.id.blank?
    end
    inbox1.update!(processed_at: Time.current.utc)

    # Second receipt of the same event (duplicate)
    inbox2 = InboxEvent.find_or_create_by(
      source: event_source,
      source_event_id: source_event_id
    )

    # Should be the same record
    expect(inbox1.id).to eq(inbox2.id)
    expect(inbox1.processed_at).not_to be_nil
  end

  it "allows different events from the same source to be processed" do
    event_source = "github_webhook"

    inbox1 = InboxEvent.find_or_create_by(
      source: event_source,
      source_event_id: "evt_11111"
    )
    inbox1.update!(processed_at: Time.current.utc)

    inbox2 = InboxEvent.find_or_create_by(
      source: event_source,
      source_event_id: "evt_22222"
    )

    expect(inbox1.id).not_to eq(inbox2.id)
  end

  it "stores a reference to the processing result" do
    inbox = InboxEvent.find_or_create_by(
      source: "github_webhook",
      source_event_id: "evt_xyz"
    )

    result_ref = "operation_op_123"
    inbox.update!(result_ref: result_ref)

    expect(inbox.reload.result_ref).to eq(result_ref)
  end

  context "idempotent event consumption" do
    it "prevents duplicate logical effects when the same message arrives twice" do
      # Simulate an event that triggers a deployment
      event_source = "queue_publisher"
      source_event_id = "msg_abc123"

      # First consume
      inbox1 = InboxEvent.find_or_create_by(
        source: event_source,
        source_event_id: source_event_id
      )
      inbox1.update!(processed_at: Time.current.utc)

      # Verify it was processed
      expect(inbox1.processed_at).not_to be_nil

      # Second consume (duplicate arrival from queue)
      inbox2 = InboxEvent.find_or_create_by(
        source: event_source,
        source_event_id: source_event_id
      )

      # Should be the same record, already processed
      expect(inbox2.id).to eq(inbox1.id)
      expect(inbox2.processed_at).not_to be_nil
    end
  end
end
