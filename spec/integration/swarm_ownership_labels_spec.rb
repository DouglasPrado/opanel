require "rails_helper"

# Ownership labels on real Swarm: AC2, AC7 — resources are labeled and reidentified.
# This runs against the real Swarm Lab (`:swarm` tag, requires daemon).
RSpec.describe "Swarm ownership labels", :swarm do
  before(:each) do
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment, desired_revision: 5) }

  describe "AC2: labels are stamped on creation" do
    it "creates a Service with the complete ownership label set" do
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(service)
      service_name = unique_namespace("svc")
      created_resources << [ "service", service_name ]

      command = ExecutorCommand.new(
        id: "test-create-#{service_name}",
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

      result = executor.execute(command)
      expect(result.outcome).to eq("APPLIED"), "create_service: #{result.error_code || 'unknown'}"
    end

    it "creates a Network with the complete ownership label set" do
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(environment)
      network_name = unique_namespace("net")
      created_resources << [ "network", network_name ]

      command = ExecutorCommand.new(
        id: "test-net-create-#{network_name}",
        type: "create_network",
        cluster_id: "test-cluster",
        resource_type: "Environment",
        resource_id: environment.id,
        payload: {
          "name" => network_name,
          "labels" => labels,
          "attachable" => true
        }
      )

      result = executor.execute(command)
      expect(result.outcome).to eq("APPLIED"), "create_network: #{result.error_code || 'unknown'}"
    end
  end

  describe "AC7: reidentification after restart (idempotent create)" do
    it "finds an existing Service by ownership labels on retry" do
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(service)
      service_name = unique_namespace("svc-reident")
      created_resources << [ "service", service_name ]

      # First create: new Service in Swarm
      command = ExecutorCommand.new(
        id: "test-create-1-#{service_name}",
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

      result1 = executor.execute(command)
      expect(result1.outcome).to eq("APPLIED"), "first create: #{result1.error_code || 'unknown'}"
      first_id = result1.runtime_resource_ids.first

      # Simulate restart and retry with same command
      executor2 = SwarmExecutor.new
      result2 = executor2.execute(command)

      # Should find and adopt
      expect(result2.outcome).to eq("NOOP"), "retry: #{result2.error_code || 'unknown'}"
      expect(result2.safe_metadata[:adopted]).to be true
      expect(result2.runtime_resource_ids.first).to be_present
      expect(result2.runtime_resource_ids.first).to eq(first_id)
    end

    it "finds an existing Network by ownership labels on retry" do
      executor = SwarmExecutor.new
      labels = Opanel::Ownership.labels_for(environment)
      network_name = unique_namespace("net-reident")
      created_resources << [ "network", network_name ]

      # First create: new Network in Swarm
      command = ExecutorCommand.new(
        id: "test-net-create-1-#{network_name}",
        type: "create_network",
        cluster_id: "test-cluster",
        resource_type: "Environment",
        resource_id: environment.external_id,
        payload: {
          "name" => network_name,
          "labels" => labels,
          "attachable" => true
        }
      )

      result1 = executor.execute(command)
      expect(result1.outcome).to eq("APPLIED"), "first create: #{result1.error_code || 'unknown'}"
      first_id = result1.runtime_resource_ids.first

      # Simulate restart and retry
      executor2 = SwarmExecutor.new
      result2 = executor2.execute(command)

      # Should find and adopt
      expect(result2.outcome).to eq("NOOP"), "retry: #{result2.error_code || 'unknown'}"
      expect(result2.safe_metadata[:adopted]).to be true
      expect(result2.runtime_resource_ids.first).to be_present
      expect(result2.runtime_resource_ids.first).to eq(first_id)
    end
  end
end
