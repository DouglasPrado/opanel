require "rails_helper"

# Foreign resources: AC4 — a resource created outside the platform is not
# recognized as owned by Opanel. This test runs against real Swarm.
RSpec.describe "Swarm foreign resources", :swarm do
  before(:each) do
    User.delete_all
    @created_services = []
    @created_networks = []
  end

  after(:each) do
    # Clean up: remove the foreign resources we created for testing
    executor = SwarmExecutor.new

    @created_services.each do |service_name|
      # We can only remove by Swarm ID; for foreign services, we need to list
      # and find by name. This is a test cleanup, not part of the platform.
      # Skip cleanup here; the test environment will clean up.
    end

    @created_networks.each do |network_name|
      # Same for networks
    end
  end

  describe "AC4: foreign resources are not recognized" do
    it "returns false for a Service without ownership labels" do
      executor = SwarmExecutor.new
      client = EngineClient.new

      # Create a Service directly via Docker API (simulating external tool)
      foreign_spec = {
        "Name" => "foreign-service-#{SecureRandom.hex(4)}",
        "Labels" => { "created_by" => "external_tool" },
        "TaskTemplate" => {
          "ContainerSpec" => { "Image" => "redis:latest" }
        },
        "Mode" => { "Replicated" => { "Replicas" => 1 } }
      }

      response = client.post("/services/create", foreign_spec)
      expect(response.ok?).to be true
      foreign_service_id = response.body["ID"]

      # Inspect the foreign service
      inspect_response = client.get("/services/#{foreign_service_id}")
      expect(inspect_response.ok?).to be true
      foreign_runtime = inspect_response.body

      # Predicate should return false: no com.opanel.managed label
      expect(Opanel::Ownership.managed_by_platform?(foreign_runtime)).to be false

      # Clean up
      client.delete("/services/#{foreign_service_id}")
    end

    it "returns false for a Service with only some Opanel labels" do
      executor = SwarmExecutor.new
      client = EngineClient.new

      # Create a Service with partial/incomplete Opanel labels (pretending to be ours but missing IDs)
      incomplete_spec = {
        "Name" => "incomplete-service-#{SecureRandom.hex(4)}",
        "Labels" => {
          "com.opanel.managed" => "true",
          "com.opanel.team_id" => "tm_01arZ3ndektsv4rrffqaev" # Fake ID
          # Missing project_id, environment_id
        },
        "TaskTemplate" => {
          "ContainerSpec" => { "Image" => "redis:latest" }
        },
        "Mode" => { "Replicated" => { "Replicas" => 1 } }
      }

      response = client.post("/services/create", incomplete_spec)
      expect(response.ok?).to be true
      incomplete_service_id = response.body["ID"]

      inspect_response = client.get("/services/#{incomplete_service_id}")
      expect(inspect_response.ok?).to be true
      incomplete_runtime = inspect_response.body

      # Predicate should return false: missing required IDs
      expect(Opanel::Ownership.managed_by_platform?(incomplete_runtime)).to be false

      # Clean up
      client.delete("/services/#{incomplete_service_id}")
    end

    it "returns false for a Network without ownership labels" do
      executor = SwarmExecutor.new
      client = EngineClient.new

      # Create a Network directly via Docker API
      foreign_network_spec = {
        "Name" => "foreign-network-#{SecureRandom.hex(4)}",
        "Driver" => "overlay",
        "Labels" => { "created_by" => "terraform" }
      }

      response = client.post("/networks/create", foreign_network_spec)
      expect(response.ok?).to be true
      foreign_network_id = response.body["Id"]

      inspect_response = client.get("/networks/#{foreign_network_id}")
      expect(inspect_response.ok?).to be true
      foreign_runtime = inspect_response.body

      # Predicate should return false
      expect(Opanel::Ownership.managed_by_platform?(foreign_runtime)).to be false

      # Clean up
      client.delete("/networks/#{foreign_network_id}")
    end
  end

  describe "AC5: ambiguous resources are not removed automatically" do
    it "logs an anomaly for a Service with managed=true but invalid IDs" do
      client = EngineClient.new

      # Create a Service claiming to be ours but with broken IDs
      ambiguous_spec = {
        "Name" => "ambiguous-service-#{SecureRandom.hex(4)}",
        "Labels" => {
          "com.opanel.managed" => "true",
          "com.opanel.team_id" => "tm_definitely_not_a_ulid",
          "com.opanel.project_id" => "prj_also_invalid",
          "com.opanel.environment_id" => "env_broken"
        },
        "TaskTemplate" => {
          "ContainerSpec" => { "Image" => "redis:latest" }
        },
        "Mode" => { "Replicated" => { "Replicas" => 1 } }
      }

      response = client.post("/services/create", ambiguous_spec)
      expect(response.ok?).to be true
      ambiguous_service_id = response.body["ID"]

      inspect_response = client.get("/services/#{ambiguous_service_id}")
      expect(inspect_response.ok?).to be true
      ambiguous_runtime = inspect_response.body

      # The predicate should log an anomaly and return false
      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("decode failed")
      ))

      result = Opanel::Ownership.managed_by_platform?(ambiguous_runtime)
      expect(result).to be false

      # The resource is NOT automatically removed; it remains in the Swarm
      # A human must decide what to do with it.
      inspect_again = client.get("/services/#{ambiguous_service_id}")
      expect(inspect_again.ok?).to be true

      # Clean up
      client.delete("/services/#{ambiguous_service_id}")
    end
  end
end
