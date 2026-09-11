require "rails_helper"

# The ownership predicate: is this runtime resource managed by the platform?
# AC5: ambiguous cases default to "not ours". A resource claiming managed=true
# with inconsistent IDs is logged as anomaly and never removed automatically.
RSpec.describe Opanel::Ownership, "managed_by_platform?" do
  before(:each) { User.delete_all }

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  # Build a Swarm Service response object matching Docker Engine API.
  def service_runtime_resource(overrides = {})
    defaults = {
      "ID" => "srv_123abc",
      "Version" => { "Index" => 100 },
      "Spec" => {
        "Name" => "test-service",
        "Labels" => {
          "com.opanel.managed" => "true",
          "com.opanel.team_id" => team.external_id,
          "com.opanel.project_id" => project.external_id,
          "com.opanel.environment_id" => environment.external_id,
          "com.opanel.service_id" => service.external_id,
          "com.opanel.desired_revision" => "1"
        },
        "TaskTemplate" => { "ContainerSpec" => {} }
      }
    }
    deep_merge(defaults, overrides)
  end

  def network_runtime_resource(overrides = {})
    defaults = {
      "Id" => "net_456def",
      "Spec" => {
        "Name" => "test-network",
        "Labels" => {
          "com.opanel.managed" => "true",
          "com.opanel.team_id" => team.external_id,
          "com.opanel.project_id" => project.external_id,
          "com.opanel.environment_id" => environment.external_id
        },
        "Driver" => "overlay"
      }
    }
    deep_merge(defaults, overrides)
  end

  describe "accepting owned resources (AC4 negative)" do
    it "returns true for a valid Service with correct labels" do
      runtime = service_runtime_resource

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be true
    end

    it "returns true for a valid Network with correct labels" do
      runtime = network_runtime_resource

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be true
    end

    it "returns true even if optional labels are missing" do
      runtime = service_runtime_resource
      # release_id is optional (Release does not exist yet)
      runtime["Spec"]["Labels"].delete("com.opanel.release_id")

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be true
    end
  end

  describe "rejecting foreign resources (AC4)" do
    it "returns false for a resource without com.opanel.managed label" do
      runtime = service_runtime_resource
      runtime["Spec"]["Labels"].delete("com.opanel.managed")

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false for a resource with managed=false" do
      runtime = service_runtime_resource
      runtime["Spec"]["Labels"]["com.opanel.managed"] = "false"

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false for a resource with no labels at all" do
      runtime = service_runtime_resource
      runtime["Spec"].delete("Labels")

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false for a non-Hash object" do
      expect(Opanel::Ownership.managed_by_platform?(nil)).to be false
      expect(Opanel::Ownership.managed_by_platform?("not a hash")).to be false
      expect(Opanel::Ownership.managed_by_platform?(123)).to be false
    end
  end

  describe "AC5: inconsistent IDs logged as anomaly, not removed" do
    it "returns false and logs when team_id decode fails" do
      runtime = service_runtime_resource
      runtime["Spec"]["Labels"]["com.opanel.team_id"] = "invalid_id"

      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("decode failed")
      ))

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false and logs when project team_id does not match" do
      runtime = service_runtime_resource
      other_team = create(:team)
      runtime["Spec"]["Labels"]["com.opanel.team_id"] = other_team.external_id
      # project still belongs to original team, so the IDs don't match

      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("does not match")
      ))

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false and logs when environment project_id does not match" do
      runtime = service_runtime_resource
      other_project = create(:project, team: team)
      runtime["Spec"]["Labels"]["com.opanel.project_id"] = other_project.external_id
      # environment still belongs to original project

      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("does not match")
      ))

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false and logs when service environment_id does not match" do
      runtime = service_runtime_resource
      other_environment = create(:environment, project: project)
      runtime["Spec"]["Labels"]["com.opanel.environment_id"] = other_environment.external_id
      # service still belongs to original environment

      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("does not match")
      ))

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false and logs when required IDs are missing" do
      runtime = service_runtime_resource
      runtime["Spec"]["Labels"].delete("com.opanel.environment_id")

      expect(Rails.logger).to receive(:warn).with(hash_including(
        event: "ownership.anomaly",
        reason: include("missing required ID labels")
      ))

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end
  end

  describe "defensive coding: default to 'not ours' on ambiguity (AC5)" do
    it "returns false when Spec is missing" do
      runtime = service_runtime_resource
      runtime.delete("Spec")

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false when any required field is missing" do
      runtime = service_runtime_resource
      runtime["Spec"].delete("Labels")

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end

    it "returns false when a referenced entity does not exist" do
      runtime = service_runtime_resource
      # Point to a team that does not exist
      runtime["Spec"]["Labels"]["com.opanel.team_id"] = "tm_01arZ3ndektsv4rrffqaev" # Fake ID

      expect(Rails.logger).to receive(:warn)

      expect(Opanel::Ownership.managed_by_platform?(runtime)).to be false
    end
  end

  private

  def deep_merge(hash1, hash2)
    hash1.merge(hash2) do |key, val1, val2|
      val1.is_a?(Hash) && val2.is_a?(Hash) ? deep_merge(val1, val2) : val2
    end
  end
end
