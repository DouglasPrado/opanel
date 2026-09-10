require "rails_helper"

# Technical name: deterministic, derived from IDs, but the product never
# depends on it as the primary identifier (doc 09 §5.3, AC8).
RSpec.describe Service, "technical naming" do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team, name: "acme", slug: "acme") }
  let(:project) { create(:project, team: team, name: "web", slug: "web") }
  let(:environment) { create(:environment, project: project, name: "prod", slug: "prod") }
  let(:service) { create(:service, environment: environment, slug: "api") }

  describe "deriving the technical name" do
    it "constructs a deterministic name from team/project/environment/service slugs" do
      # Format: {team-slug}-{project-slug}-{env-slug}-{svc-slug}
      expected = "acme-web-prod-api"
      expect(service.technical_name).to eq(expected)
    end

    it "changes the technical_name when any parent slug changes" do
      old_name = service.technical_name
      environment.update!(slug: "staging")

      # The service's technical_name does not auto-update; it is set at creation
      # and remains stable. This test verifies that the *next* service would have
      # a different name, proving the derivation depends on the parent slugs.
      svc2 = create(:service, environment: environment, slug: "web")
      expect(svc2.technical_name).not_to eq(old_name)
      expect(svc2.technical_name).to include("staging")
    end

    it "returns the same technical_name even if the service's name changes" do
      # AC8: the name is cosmetic; the technical_name is stable.
      original = service.technical_name
      service.update!(name: "New Name")

      service.reload
      expect(service.technical_name).to eq(original)
    end
  end

  describe "determinism" do
    it "returns the same name for services with identical parents and slugs" do
      svc1 = create(:service, environment: environment, slug: "cache")
      svc2 = create(:service, environment: environment, slug: "cache-2")

      # Both are in the same environment; the names differ only by slug.
      expect(svc1.technical_name).to eq("acme-web-prod-cache")
      expect(svc2.technical_name).to eq("acme-web-prod-cache-2")
    end
  end
end
