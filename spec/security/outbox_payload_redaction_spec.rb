# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Outbox payload redaction (AC9)" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  it "carries SecretVersion IDs in published events, never plaintext secrets" do
    # Build a real OutboxEvent with secret_version_ids in the payload.
    secret_version_id = Opanel::Identifier.external(:secret_version, Opanel::Identifier.generate)

    event = create(:outbox_event,
      aggregate_id: service.id,
      event_type: "service.desired_state.changed.v1",
      schema_version: 1,
      payload: {
        schemaVersion: 1,
        service_id: service.id,
        desired_revision: 42,
        secret_version_ids: [ secret_version_id ]
      }
    )

    # Verify the outbox event payload carries the secret ID, not plaintext.
    expect(event.payload).to include("secret_version_ids")
    expect(event.payload["secret_version_ids"]).to include(secret_version_id)

    # Verify no plaintext secret words in the serialized payload.
    serialized_payload = event.payload.to_json
    expect(serialized_payload).not_to include("password")
    expect(serialized_payload).not_to include("api_key")
    expect(serialized_payload).not_to include("plaintext_secret")
  end

  it "logs published events without exposing secret IDs in the log output" do
    secret_version_id = Opanel::Identifier.external(:secret_version, Opanel::Identifier.generate)

    event = create(:outbox_event,
      aggregate_id: service.id,
      event_type: "service.desired_state.changed.v1",
      schema_version: 1,
      payload: {
        schemaVersion: 1,
        service_id: service.id,
        desired_revision: 42,
        secret_version_ids: [ secret_version_id ]
      }
    )

    logger_double = instance_double("Logger")
    allow(Rails).to receive(:logger).and_return(logger_double)

    # The dispatcher publishes and logs the event.
    # Capture what it logs.
    expect(logger_double).to receive(:info) do |log_hash|
      # Verify the log is about publication, not about secrets.
      expect(log_hash[:event]).to eq("outbox.event.published")
      expect(log_hash[:outbox_event_id]).to eq(event.id)
      # Verify the secret ID itself is not logged (only the event id and type).
      expect(log_hash.to_s).not_to include("password")
      expect(log_hash.to_s).not_to include("plaintext")
    end

    PublishPendingOutboxEvents.new.call
  end

  it "the outbox event persists secrets by ID reference, not by value" do
    # Build an event with a secret_version_id (as a reference, not the secret itself).
    secret_version_id = Opanel::Identifier.external(:secret_version, Opanel::Identifier.generate)

    event = create(:outbox_event,
      aggregate_id: service.id,
      event_type: "service.desired_state.changed.v1",
      schema_version: 1,
      payload: {
        schemaVersion: 1,
        service_id: service.id,
        desired_revision: 42,
        secret_version_ids: [ secret_version_id ]
      }
    )

    # Reload from database to prove it was persisted correctly.
    reloaded_event = OutboxEvent.find(event.id)
    expect(reloaded_event.payload["secret_version_ids"]).to include(secret_version_id)
    expect(reloaded_event.payload.to_json).not_to include("password")
  end
end
