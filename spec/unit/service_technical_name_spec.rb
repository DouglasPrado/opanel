require "rails_helper"

# Technical name: deterministic, derived from opaque IDs, not slugs (doc 09 §5.3,
# SC-09 resolved in favour of IDs, AC3). The name is stable even if a parent is
# renamed; the product never depends on it as a primary identifier (AC8).
RSpec.describe Service, "technical naming" do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team, name: "acme", slug: "acme") }
  let(:project) { create(:project, team: team, name: "web", slug: "web") }
  let(:environment) { create(:environment, project: project, name: "prod", slug: "prod") }
  let(:service) { create(:service, environment: environment, slug: "api") }

  describe "deriving the technical name from IDs" do
    it "constructs a deterministic name from project/environment/service IDs" do
      # Format: svc_<projectId>_<environmentId>_<serviceId> (doc 08 §5, M01-16 AC3)
      expected = "svc_#{project.external_id}_#{environment.external_id}_#{service.external_id}"
      expect(service.technical_name).to eq(expected)
    end

    it "does not change when the service's slug changes" do
      # SC-09 resolution: names come from IDs, not slugs. Renaming the Service
      # must not change its technical_name or cause a Swarm recreation (AC3).
      original = service.technical_name
      service.update!(slug: "web-api")

      service.reload
      expect(service.technical_name).to eq(original)
    end

    it "does not change when a parent project slug changes" do
      # AC3: renaming a parent does not change the technical name.
      original = service.technical_name
      project.update!(slug: "backend")

      service.reload
      expect(service.technical_name).to eq(original)
    end

    it "does not change when a parent environment slug changes" do
      # AC3: renaming a parent does not change the technical name.
      original = service.technical_name
      environment.update!(slug: "staging")

      service.reload
      expect(service.technical_name).to eq(original)
    end

    it "does not change when the parent team slug changes" do
      # AC3: renaming a parent does not change the technical name.
      original = service.technical_name
      team.update!(slug: "example")

      service.reload
      expect(service.technical_name).to eq(original)
    end

    it "returns the same technical_name even if the service's name changes" do
      # The name is cosmetic; the technical_name is stable (AC8).
      original = service.technical_name
      service.update!(name: "New Descriptive Name")

      service.reload
      expect(service.technical_name).to eq(original)
    end
  end

  describe "determinism and collision resistance" do
    it "returns different names for services with different IDs in the same environment" do
      svc1 = create(:service, environment: environment, slug: "cache")
      svc2 = create(:service, environment: environment, slug: "cache-2")

      # Same environment, different IDs → different names
      expect(svc1.technical_name).not_to eq(svc2.technical_name)
    end

    it "returns the same name for the same service called multiple times" do
      name1 = service.technical_name
      name2 = service.technical_name

      # Deterministic: same input, same output
      expect(name1).to eq(name2)
    end

    it "uses the opaque IDs, which are collision-proof by construction" do
      # ULIDs are unique (AC8), so the derived name is collision-proof.
      # This test documents the property; it does not prove ULIDs (that is
      # ADR-0002's responsibility).
      name = service.technical_name

      # Pattern: svc_<projectId>_<environmentId>_<serviceId> where each ID is prefix_ULID
      # Example: svc_prj_01HX...._env_01HX...._svc_01HX....
      ulid_pattern = '[0-9A-HJKMNP-TV-Z]{26}'
      pattern = /\Asvc_[a-z]+_#{ulid_pattern}_[a-z]+_#{ulid_pattern}_[a-z]+_#{ulid_pattern}\z/
      expect(name).to match(pattern)
    end
  end
end
