require "rails_helper"

# Reidentification after restart: AC7 — the platform loses all in-memory state
# and must re-derive ownership from what Swarm reports in labels.
# This test verifies that reading back ownership labels is sufficient.
RSpec.describe "Swarm ownership reidentification", :swarm do
  before(:each) do
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment, desired_revision: 3) }

  describe "AC7: reidentification from labels alone" do
    it "re-derives ownership from Swarm labels after Control Plane restart" do
      # Step 1: Create a Service with ownership labels
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(service)
      service_name = unique_namespace("reident")
      created_resources << [ "service", service_name ]

      create_command = ExecutorCommand.new(
        id: "test-create",
        type: "create_service",
        cluster_id: "test-cluster",
        resource_type: "Service",
        resource_id: service.id,
        payload: {
          "name" => service_name,
          "image" => "redis:latest",
          "replicas" => 1,
          "labels" => labels,
          "networks" => []
        }
      )

      result = executor.execute(create_command)
      expect(result.applied?).to be true

      # Step 2: Simulate complete Control Plane restart
      # In real life: all in-memory state is gone, database is queried fresh,
      # labels and IDs are read from what Swarm reports. Here we simulate by:
      # - Forgetting the runtime resource ID
      # - Reading it back from Swarm
      # - Verifying the predicate works

      # Use a fresh client/executor (simulating a new process)
      executor2 = SwarmExecutor.new
      client = EngineClient.new

      # Step 3: List all services and find ours by label
      filter = JSON.generate("label" => [
        "com.opanel.service_id=#{service.external_id}"
      ])
      list_response = client.get("/services?filters=#{CGI.escape(filter)}")
      expect(list_response.ok?).to be true

      services = Array(list_response.body)
      expect(services.length).to eq(1)

      runtime_service = services.first

      # Step 4: Verify the predicate correctly identifies this as ours
      # using ONLY what Swarm reports (labels)
      expect(Opanel::Ownership.managed_by_platform?(runtime_service)).to be true

      # Step 5: Verify the labels are exactly what we can re-read from Swarm
      swarm_labels = runtime_service.dig("Spec", "Labels") || {}

      expect(swarm_labels["com.opanel.managed"]).to eq("true")
      expect(swarm_labels["com.opanel.team_id"]).to eq(team.external_id)
      expect(swarm_labels["com.opanel.project_id"]).to eq(project.external_id)
      expect(swarm_labels["com.opanel.environment_id"]).to eq(environment.external_id)
      expect(swarm_labels["com.opanel.service_id"]).to eq(service.external_id)
      expect(swarm_labels["com.opanel.desired_revision"]).to eq("3")
    end

    it "re-identifies multiple Services correctly after restart" do
      executor = SwarmExecutor.new
      client = EngineClient.new

      # Create two Services with distinct ownership labels
      service2 = create(:service, environment: environment)
      labels1 = Opanel::Ownership.labels_for(service)
      labels2 = Opanel::Ownership.labels_for(service2)

      service_name_1 = unique_namespace("reident")
      service_name_2 = unique_namespace("reident")
      created_resources << [ "service", service_name_1 ]
      created_resources << [ "service", service_name_2 ]

      cmd1 = ExecutorCommand.new(
        id: "test-create-1",
        type: "create_service",
        cluster_id: "test-cluster",
        resource_type: "Service",
        resource_id: service.id,
        payload: {
          "name" => service_name_1,
          "image" => "redis:latest",
          "replicas" => 1,
          "labels" => labels1,
          "networks" => []
        }
      )

      cmd2 = ExecutorCommand.new(
        id: "test-create-2",
        type: "create_service",
        cluster_id: "test-cluster",
        resource_type: "Service",
        resource_id: service2.id,
        payload: {
          "name" => service_name_2,
          "image" => "redis:latest",
          "replicas" => 1,
          "labels" => labels2,
          "networks" => []
        }
      )

      result1 = executor.execute(cmd1)
      result2 = executor.execute(cmd2)
      expect(result1.applied?).to be true
      expect(result2.applied?).to be true

      # Simulate restart: list all our Services
      filter = JSON.generate("label" => [
        "com.opanel.environment_id=#{environment.external_id}"
      ])
      list_response = client.get("/services?filters=#{CGI.escape(filter)}")
      expect(list_response.ok?).to be true

      services = Array(list_response.body)
      expect(services.length).to eq(2)

      # Both should be identified correctly
      services.each do |runtime_service|
        expect(Opanel::Ownership.managed_by_platform?(runtime_service)).to be true
        labels = runtime_service.dig("Spec", "Labels") || {}
        expect(labels["com.opanel.managed"]).to eq("true")
        expect(labels["com.opanel.service_id"]).to be_present
      end

      # Verify the two services have different service_id labels
      service_ids = services.map { |s| s.dig("Spec", "Labels", "com.opanel.service_id") }
      expect(service_ids.uniq.length).to eq(2)
    end

    it "correctly rejects a foreign Service after listing" do
      client = EngineClient.new
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(service)
      owned_name = unique_namespace("owned")
      foreign_name = unique_namespace("foreign")
      created_resources << [ "service", owned_name ]
      created_resources << [ "service", foreign_name ]

      # Create one of ours
      owned_spec = {
        "Name" => owned_name,
        "Labels" => labels,
        "TaskTemplate" => {
          "ContainerSpec" => { "Image" => "redis:latest" }
        },
        "Mode" => { "Replicated" => { "Replicas" => 1 } }
      }

      response = client.post("/services/create", owned_spec)
      expect(response.ok?).to be true
      owned_id = response.body["ID"]

      # Create a foreign one in the same environment
      foreign_spec = {
        "Name" => foreign_name,
        "Labels" => { "team" => team.slug }, # Not our labels
        "TaskTemplate" => {
          "ContainerSpec" => { "Image" => "postgres:latest" }
        },
        "Mode" => { "Replicated" => { "Replicas" => 1 } }
      }

      response = client.post("/services/create", foreign_spec)
      expect(response.ok?).to be true
      foreign_id = response.body["ID"]

      # Simulate restart: list all services (without our filter)
      list_response = client.get("/services")
      expect(list_response.ok?).to be true

      services = Array(list_response.body)

      # Find ours and the foreign one
      owned = services.find { |s| s["ID"] == owned_id }
      foreign = services.find { |s| s["ID"] == foreign_id }

      # Our service is identified as owned
      expect(Opanel::Ownership.managed_by_platform?(owned)).to be true

      # Foreign service is not
      expect(Opanel::Ownership.managed_by_platform?(foreign)).to be false

      # Clean up
      client.delete("/services/#{owned_id}")
      client.delete("/services/#{foreign_id}")
    end
  end
end
