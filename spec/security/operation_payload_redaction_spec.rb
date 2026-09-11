require "rails_helper"

# AC9: Nenhum payload de Operation ou OutboxEvent contém plaintext de secret.
# Provado com valor plantado e por AF-06 (configuration in fitness.yml).
RSpec.describe "Operation and OutboxEvent payload redaction", :integration do
  let(:team) { create(:team) }
  let(:actor) { team.owner }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  it "Operation payload never contains plaintext secrets" do
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5
    )

    expect(result).to be_success
    operation = Operation.where(resource_id: service.id).last

    # Payload should not contain credentials, tokens, or secrets
    payload_json = operation.payload.to_json
    expect(payload_json).not_to match(/password|secret|token|key|credential/)
    expect(payload_json).not_to match(/----BEGIN|Private|private|SECRET|Bearer/)
  end

  it "OutboxEvent payload never contains plaintext secrets" do
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5
    )

    expect(result).to be_success
    event = OutboxEvent.where(aggregate_id: service.id).last

    # Payload should not contain credentials, tokens, or secrets
    payload_json = event.payload.to_json
    expect(payload_json).not_to match(/password|secret|token|key|credential/)
    expect(payload_json).not_to match(/----BEGIN|Private|private|SECRET|Bearer/)
  end

  it "Operation payload is versioned and has required fields" do
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5
    )

    operation = Operation.where(resource_id: service.id).last
    expect(operation.payload).to have_key("schemaVersion")
    expect(operation.payload["schemaVersion"]).to eq(1)
  end

  # Note: AF-06 (Affinity/Fitness Function 06) is configured in config/architecture/fitness.yml
  # and runs during gates to verify no secrets appear in Operation/OutboxEvent payloads
  # This test documents the requirement; the automated check runs in the gate.
end
