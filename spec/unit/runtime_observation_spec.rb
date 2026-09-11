require "rails_helper"

RSpec.describe Opanel::RuntimeObservation do
  describe "initialization and validation" do
    it "creates a valid observation with all fields" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "abcd1234",
        name: "my-network",
        labels: { "com.opanel.managed" => "true", "com.opanel.team_id" => "team_01abc" },
        version: 123,
        attributes: { "driver" => "overlay", "scope" => "swarm" }
      )

      expect(obs.kind).to eq("network")
      expect(obs.runtime_id).to eq("abcd1234")
      expect(obs.name).to eq("my-network")
      expect(obs.labels).to eq({ "com.opanel.managed" => "true", "com.opanel.team_id" => "team_01abc" })
      expect(obs.version).to eq(123)
      expect(obs.attributes).to eq({ "driver" => "overlay", "scope" => "swarm" })
    end

    it "accepts service kind" do
      obs = Opanel::RuntimeObservation.new(
        kind: "service",
        runtime_id: "svc123",
        name: "my-service",
        labels: {},
        version: 5,
        attributes: { "image" => "nginx:latest", "replicas" => 2, "mode" => "replicated" }
      )
      expect(obs.kind).to eq("service")
    end

    it "accepts node kind" do
      obs = Opanel::RuntimeObservation.new(
        kind: "node",
        runtime_id: "node123",
        name: "manager-1",
        labels: {},
        version: 10,
        attributes: { "role" => "manager", "state" => "ready" }
      )
      expect(obs.kind).to eq("node")
    end

    it "raises on invalid kind" do
      expect {
        Opanel::RuntimeObservation.new(
          kind: "invalid",
          runtime_id: "test",
          name: "test",
          labels: {},
          version: nil,
          attributes: {}
        )
      }.to raise_error(ArgumentError, /invalid kind/)
    end
  end

  describe "labels handling" do
    it "defaults labels to empty hash if not provided" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test-net",
        labels: nil,
        version: 1,
        attributes: {}
      )
      expect(obs.labels).to eq({})
    end

    it "keeps labels flat (does not nest)" do
      labels = {
        "com.opanel.managed" => "true",
        "com.opanel.team_id" => "team_01",
        "com.opanel.environment_id" => "env_01"
      }
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test-net",
        labels: labels,
        version: 1,
        attributes: {}
      )
      expect(obs.labels).to eq(labels)
      expect(obs.labels).to be_frozen
    end
  end

  describe "attributes allowlist" do
    it "network attributes are preserved" do
      attrs = { "driver" => "overlay", "scope" => "swarm", "attachable" => true, "internal" => false }
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test",
        labels: {},
        version: 1,
        attributes: attrs
      )
      expect(obs.attributes).to eq(attrs)
    end

    it "service attributes are preserved" do
      attrs = { "image" => "nginx:latest", "replicas" => 3, "mode" => "replicated" }
      obs = Opanel::RuntimeObservation.new(
        kind: "service",
        runtime_id: "svc123",
        name: "test",
        labels: {},
        version: 1,
        attributes: attrs
      )
      expect(obs.attributes).to eq(attrs)
    end

    it "node attributes are preserved" do
      attrs = { "role" => "manager", "availability" => "active", "state" => "ready", "hostname" => "host1",
"advertise_address" => "192.168.1.1" }
      obs = Opanel::RuntimeObservation.new(
        kind: "node",
        runtime_id: "node123",
        name: "test",
        labels: {},
        version: 1,
        attributes: attrs
      )
      expect(obs.attributes).to eq(attrs)
    end

    it "attributes are JSON-serializable" do
      attrs = { "replicas" => 2, "bool" => true, "null_val" => nil }
      obs = Opanel::RuntimeObservation.new(
        kind: "service",
        runtime_id: "svc123",
        name: "test",
        labels: {},
        version: 1,
        attributes: attrs
      )
      json = JSON.generate(obs.to_h)
      parsed = JSON.parse(json)
      expect(parsed["attributes"]).to eq({ "replicas" => 2, "bool" => true, "null_val" => nil })
    end
  end

  describe "version handling" do
    it "accepts integer version" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test",
        labels: {},
        version: 42,
        attributes: {}
      )
      expect(obs.version).to eq(42)
    end

    it "accepts nil version" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test",
        labels: {},
        version: nil,
        attributes: {}
      )
      expect(obs.version).to be_nil
    end
  end

  describe "inspect and to_s redaction" do
    it "does not dump full body in inspect" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "abcd1234567890",
        name: "production-network",
        labels: { "secret_label" => "secret_value" },
        version: 999,
        attributes: { "secret_attr" => "secret" }
      )

      inspect_str = obs.inspect
      # Inspect should not contain the full values
      expect(inspect_str).not_to include("secret_value")
      expect(inspect_str).not_to include("production-network")
      # Should mention kind and show truncated id
      expect(inspect_str).to include("network")
      expect(inspect_str).to match(/abcd/)
    end

    it "to_s returns redacted summary" do
      obs = Opanel::RuntimeObservation.new(
        kind: "service",
        runtime_id: "long-service-id-here",
        name: "api-service",
        labels: { "k1" => "v1", "k2" => "v2" },
        version: 5,
        attributes: { "image" => "secret-registry/image", "replicas" => 3 }
      )

      str = obs.to_s
      expect(str).not_to include("secret-registry")
      expect(str).not_to include("api-service")
      expect(str).to include("service")
    end
  end

  describe "data object contract" do
    it "is frozen" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test",
        labels: {},
        version: 1,
        attributes: {}
      )
      expect(obs.frozen?).to be true
    end

    it "has all six fields" do
      obs = Opanel::RuntimeObservation.new(
        kind: "network",
        runtime_id: "net123",
        name: "test",
        labels: { "k" => "v" },
        version: 1,
        attributes: { "a" => "b" }
      )

      expect(obs.respond_to?(:kind)).to be true
      expect(obs.respond_to?(:runtime_id)).to be true
      expect(obs.respond_to?(:name)).to be true
      expect(obs.respond_to?(:labels)).to be true
      expect(obs.respond_to?(:version)).to be true
      expect(obs.respond_to?(:attributes)).to be true
    end
  end
end
