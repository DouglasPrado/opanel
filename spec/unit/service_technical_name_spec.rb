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
    it "constructs a deterministic name from the service ID" do
      # Format: svc_<serviceId>, where <serviceId> is the ADR-0002 external id
      # (doc 09 §195; DECISIONS.md 2026-09-11, the shortening arbitration).
      # `svc_` + `svc_` + 26 ULID characters = 34, inside the Engine's limit of 63.
      expected = "svc_#{service.external_id}"
      expect(service.technical_name).to eq(expected)
      expect(service.technical_name.length).to be <= 63
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

    it "uses the opaque ID, which is collision-proof by construction" do
      # ULIDs are unique (AC8), so the derived name is collision-proof.
      # This test documents the property; it does not prove ULIDs (that is
      # ADR-0002's responsibility).
      name = service.technical_name

      # Pattern: svc_<serviceId>, where serviceId is itself prefix_ULID
      # Example: svc_svc_01HX....
      # Maximum length: 4 + 4 + 26 = 34 characters, inside the Engine's 63.
      ulid_pattern = '[0-9A-HJKMNP-TV-Z]{26}'
      pattern = /\Asvc_[a-z]+_#{ulid_pattern}\z/
      expect(name).to match(pattern)
      expect(name.length).to be <= 63
    end
  end
end
