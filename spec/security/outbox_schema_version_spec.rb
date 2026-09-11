# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Outbox event schema version validation (AC8)" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  context "column schema_version validation" do
    it "rejects an event with unknown schema_version column" do
      # The OutboxEvent.schema_version column must match a known version
      # for the event_type.
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 999  # Unknown column version
      )

      dispatcher = PublishPendingOutboxEvents.new
      dispatcher.call

      # Event should remain unpublished
      expect(event.reload.published_at).to be_nil
    end

    it "publishes an event with a known schema_version column" do
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 1  # Known column version
      )

      dispatcher = PublishPendingOutboxEvents.new
      dispatcher.call

      # Event should be published
      expect(event.reload.published_at).not_to be_nil
    end
  end

  context "payload schemaVersion field validation" do
    it "rejects if payload schemaVersion disagrees with column schema_version" do
      # Payload and column must agree: if column says 1, payload's schemaVersion must also be 1.
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 1,
        payload: {
          schemaVersion: 2  # Disagrees with column
        }
      )

      dispatcher = PublishPendingOutboxEvents.new
      dispatcher.call

      # Should not be published due to mismatch
      expect(event.reload.published_at).to be_nil
    end

    it "publishes when column and payload schemaVersion agree" do
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 1,
        payload: {
          schemaVersion: 1  # Agrees with column
        }
      )

      dispatcher = PublishPendingOutboxEvents.new
      dispatcher.call

      # Should be published
      expect(event.reload.published_at).not_to be_nil
    end
  end

  context "validating event-type schemas" do
    it "rejects an event with unknown schemaVersion" do
      # Create an event with an unknown schema version
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 999  # Unknown version
      )

      dispatcher = PublishPendingOutboxEvents.new

      # The dispatcher should validate and skip this event
      # (not publish it, not mark it published, not delete it)
      expect {
        dispatcher.call
      }.not_to raise_error

      # Event should remain unpublished
      expect(event.reload.published_at).to be_nil
    end

    it "logs rejected events with their id and type for observability" do
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v999",
        schema_version: 999
      )

      logger_double = instance_double("Logger")
      allow(Rails).to receive(:logger).and_return(logger_double)

      expect(logger_double).to receive(:warn).with(
        hash_including(
          event: "outbox.event.schema_unknown",
          outbox_event_id: event.id,
          event_type: event.event_type
        )
      )

      PublishPendingOutboxEvents.new.call
    end

    it "publishes events with known schemaVersion" do
      event = create(:outbox_event,
        aggregate_id: service.id,
        event_type: "service.desired_state.changed.v1",
        schema_version: 1
      )

      PublishPendingOutboxEvents.new.call

      # Known versions should be published
      expect(event.reload.published_at).not_to be_nil
    end
  end

  context "event-type allowlist" do
    it "maintains an allowlist of known event types and their versions" do
      # The allowlist should be accessible for testing
      allow_list = Opanel::OperationPayload::EVENT_SCHEMAS

      expect(allow_list).to be_a(Hash)
      expect(allow_list).not_to be_empty

      # Each event type should have a schema definition
      allow_list.each do |event_type, schema|
        expect(schema).to have_key(:schema_version)
        expect(schema).to have_key(:fields)
      end
    end

    it "validates operation type payloads against their schema" do
      valid_payload = {
        schemaVersion: Opanel::OperationPayload::UPDATE_SERVICE_DESIRED_STATE_V1,
        service_id: "svc_123",
        desired_revision: 42
      }

      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", valid_payload)
      expect(valid).to be true
      expect(error).to be_nil
    end

    it "rejects payloads with unexpected fields" do
      invalid_payload = {
        schemaVersion: Opanel::OperationPayload::UPDATE_SERVICE_DESIRED_STATE_V1,
        service_id: "svc_123",
        malicious_field: "DROP TABLE operations"
      }

      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", invalid_payload)
      expect(valid).to be false
      expect(error).to include("Unexpected fields")
    end
  end
end
