require "rails_helper"

RSpec.describe Opanel::OperationPayload, ".validation" do
  describe ".valid?" do
    let(:valid_payload) do
      {
        schemaVersion: 1,
        service_id: "svc_123456789012345678901234",
        desired_revision: 5,
        replicas: 3,
        image_ref: "myregistry.io/app:v1.0",
        image_digest: "sha256:abcd1234",
        ports: { "8080" => "8080" },
        health_check: { "type" => "http", "path" => "/health" },
        cpu_reservation: "500m",
        cpu_limit: "1000m",
        memory_reservation: "256Mi",
        memory_limit: "512Mi",
        constraints: {},
        correlation_id: "corr_123",
        request_id: "req_123",
        actor_id: "usr_123"
      }
    end

    it "accepts a valid UPDATE_SERVICE payload" do
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", valid_payload)
      expect(valid).to be true
      expect(error).to be_nil
    end

    it "rejects unknown operation types" do
      valid, error = Opanel::OperationPayload.valid?("UNKNOWN_TYPE", valid_payload)
      expect(valid).to be false
      expect(error).to include("Unknown operation type")
    end

    it "rejects payload with missing schema_version" do
      payload = valid_payload.dup
      payload.delete(:schemaVersion)
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", payload)
      expect(valid).to be false
      expect(error).to include("schemaVersion mismatch")
    end

    it "rejects payload with incorrect schema_version" do
      payload = valid_payload.dup
      payload[:schemaVersion] = 999
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", payload)
      expect(valid).to be false
      expect(error).to include("schemaVersion mismatch")
    end

    it "rejects payload with unexpected fields" do
      payload = valid_payload.dup
      payload[:secret_plaintext] = "super_secret"  # Not in allowed fields
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", payload)
      expect(valid).to be false
      expect(error).to include("Unexpected fields")
    end

    it "accepts payload with symbol keys" do
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", valid_payload)
      expect(valid).to be true
    end

    it "accepts payload with string keys" do
      stringified = valid_payload.transform_keys(&:to_s)
      valid, error = Opanel::OperationPayload.valid?("UPDATE_SERVICE", stringified)
      expect(valid).to be true
    end
  end

  describe ".validate!" do
    let(:valid_payload) do
      {
        schemaVersion: 1,
        service_id: "svc_123456789012345678901234",
        desired_revision: 5,
        replicas: 3,
        image_ref: "myregistry.io/app:v1.0",
        image_digest: "sha256:abcd1234",
        ports: {},
        health_check: nil,
        cpu_reservation: nil,
        cpu_limit: nil,
        memory_reservation: nil,
        memory_limit: nil,
        constraints: nil,
        correlation_id: "corr_123",
        request_id: "req_123",
        actor_id: "usr_123"
      }
    end

    it "does not raise for valid payload" do
      expect { Opanel::OperationPayload.validate!("UPDATE_SERVICE", valid_payload) }.not_to raise_error
    end

    it "raises ArgumentError for invalid payload" do
      payload = valid_payload.dup
      payload[:secret_plaintext] = "unsafe"
      expect { Opanel::OperationPayload.validate!("UPDATE_SERVICE", payload) }.to raise_error(ArgumentError)
    end
  end
end
