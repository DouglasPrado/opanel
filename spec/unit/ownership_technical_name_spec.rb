require "rails_helper"

# Technical name: deterministic, derived from IDs, stable across renames (AC3, AC8).
RSpec.describe Opanel::Ownership, "technical_name_for" do
  before(:each) { User.delete_all }

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  describe "generating names from IDs" do
    it "generates svc_<serviceId> for a Service (AC3)" do
      name = Opanel::Ownership.technical_name_for(service)

      expected = "svc_#{service.external_id}"
      expect(name).to eq(expected)
    end

    it "generates net_<environmentId> for an Environment (AC3)" do
      name = Opanel::Ownership.technical_name_for(environment)

      expected = "net_#{environment.external_id}"
      expect(name).to eq(expected)
    end

    it "raises for unsupported resource types" do
      unsupported = double("UnsupportedResource")
      expect { Opanel::Ownership.technical_name_for(unsupported) }
        .to raise_error(ArgumentError, /does not support/)
    end

    it "respects the Engine's 63-character limit for Service names" do
      name = Opanel::Ownership.technical_name_for(service)

      # Engine constraint: "name must be 63 characters or fewer" (HTTP 400 if exceeded)
      expect(name.length).to be <= 63
    end

    it "respects the Engine's 63-character limit for Environment (network) names" do
      name = Opanel::Ownership.technical_name_for(environment)

      # Engine constraint: "name must be 63 characters or fewer" (HTTP 400 if exceeded)
      expect(name.length).to be <= 63
    end
  end

  describe "AC8: collision resistance" do
    it "produces different names for different Service IDs in the same environment" do
      svc1 = create(:service, environment: environment)
      svc2 = create(:service, environment: environment)

      name1 = Opanel::Ownership.technical_name_for(svc1)
      name2 = Opanel::Ownership.technical_name_for(svc2)

      # Different IDs → different names
      expect(name1).not_to eq(name2)
    end

    it "produces different names for the same Service in different Environments" do
      env2 = create(:environment, project: project)
      svc_in_env1 = service
      svc_in_env2 = create(:service, environment: env2)

      name1 = Opanel::Ownership.technical_name_for(svc_in_env1)
      name2 = Opanel::Ownership.technical_name_for(svc_in_env2)

      # Different environment IDs → different names
      expect(name1).not_to eq(name2)
    end

    it "produces different names for the same Environment in different Projects" do
      proj2 = create(:project, team: team)
      env_in_proj1 = environment
      env_in_proj2 = create(:environment, project: proj2)

      name1 = Opanel::Ownership.technical_name_for(env_in_proj1)
      name2 = Opanel::Ownership.technical_name_for(env_in_proj2)

      # Different project IDs → different names
      expect(name1).not_to eq(name2)
    end
  end

  describe "AC3: stable across renames" do
    it "does not change when the Service is renamed" do
      original_name = Opanel::Ownership.technical_name_for(service)

      service.update!(name: "Completely New Name", slug: "new-slug")

      new_name = Opanel::Ownership.technical_name_for(service)
      expect(new_name).to eq(original_name)
    end

    it "does not change when the Environment is renamed" do
      svc_original_name = Opanel::Ownership.technical_name_for(service)
      env_original_name = Opanel::Ownership.technical_name_for(environment)

      environment.update!(name: "Staging", slug: "staging")

      expect(Opanel::Ownership.technical_name_for(service)).to eq(svc_original_name)
      expect(Opanel::Ownership.technical_name_for(environment)).to eq(env_original_name)
    end

    it "does not change when the Project is renamed" do
      svc_original_name = Opanel::Ownership.technical_name_for(service)
      env_original_name = Opanel::Ownership.technical_name_for(environment)

      project.update!(name: "Backend Services", slug: "backend")

      expect(Opanel::Ownership.technical_name_for(service)).to eq(svc_original_name)
      expect(Opanel::Ownership.technical_name_for(environment)).to eq(env_original_name)
    end

    it "does not change when the Team is renamed" do
      svc_original_name = Opanel::Ownership.technical_name_for(service)

      team.update!(name: "Another Company", slug: "another")

      expect(Opanel::Ownership.technical_name_for(service)).to eq(svc_original_name)
    end
  end

  describe "determinism" do
    it "returns the same name every time for the same resource" do
      name1 = Opanel::Ownership.technical_name_for(service)
      name2 = Opanel::Ownership.technical_name_for(service)
      name3 = Opanel::Ownership.technical_name_for(service)

      expect(name1).to eq(name2)
      expect(name2).to eq(name3)
    end
  end
end
