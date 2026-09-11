require "rails_helper"

# Ownership labels: the complete set that identifies a resource as managed by
# the platform (doc 07 §7, ADR-0001, AC1, AC2, AC6).
RSpec.describe Opanel::Ownership, "labels_for" do
  before(:each) { User.delete_all }

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment, desired_revision: 42) }

  describe "AC1: constant namespace, no literals elsewhere" do
    it "defines the namespace as a constant appearing exactly here" do
      # The namespace should be constant and accessed through the module.
      expect(Opanel::Ownership::NAMESPACE).to eq("com.opanel")

      # After this Story, `grep -rn "com\.opanel" app lib` should return only
      # lib/opanel/ownership.rb. This test documents the invariant.
      expect(Opanel::Ownership::LABEL_KEYS).to be_a(Array)
      expect(Opanel::Ownership::LABEL_KEYS).to include("managed", "team_id", "project_id")
    end
  end

  describe "AC2: full label set for resources" do
    it "returns all labels for a Service" do
      labels = Opanel::Ownership.labels_for(service)

      # All required keys present, with com.opanel prefix.
      expect(labels["com.opanel.managed"]).to eq("true")
      expect(labels["com.opanel.team_id"]).to eq(team.external_id)
      expect(labels["com.opanel.project_id"]).to eq(project.external_id)
      expect(labels["com.opanel.environment_id"]).to eq(environment.external_id)
      expect(labels["com.opanel.service_id"]).to eq(service.external_id)
      expect(labels["com.opanel.desired_revision"]).to eq("42")

      # release_id is omitted when Release does not exist (yet).
      expect(labels["com.opanel.release_id"]).to be_nil
    end

    it "returns labels for an Environment (no service_id)" do
      labels = Opanel::Ownership.labels_for(environment)

      # Environment is a network owner; no service_id.
      expect(labels["com.opanel.managed"]).to eq("true")
      expect(labels["com.opanel.team_id"]).to eq(team.external_id)
      expect(labels["com.opanel.project_id"]).to eq(project.external_id)
      expect(labels["com.opanel.environment_id"]).to eq(environment.external_id)

      # Service-specific labels absent.
      expect(labels["com.opanel.service_id"]).to be_nil
      expect(labels["com.opanel.release_id"]).to be_nil
    end
  end

  describe "AC6: no sensitive values in labels" do
    it "contains only IDs and revision, never names or secrets" do
      labels = Opanel::Ownership.labels_for(service)

      # The service name, slug, project slug, environment slug and team names
      # must not appear anywhere in the labels.
      name_like_values = [
        service.name, service.slug,
        environment.name, environment.slug,
        project.name, project.slug,
        team.name, team.slug
      ]

      labels.each do |key, value|
        # Key should be the namespace + a label name, never a slug or name.
        expect(key).to start_with("com.opanel.")
        # Value should be an ID or number, never a name or secret.
        name_like_values.each do |name|
          expect(value).not_to include(name) if name.present?
        end
      end
    end

    it "contains only opaque identifiers, never credentials" do
      labels = Opanel::Ownership.labels_for(service)

      # All values that look like IDs should be in external form (prefixed ULID).
      # None should be raw ULID or contain anything that looks like a credential.
      id_labels = %w[team_id project_id environment_id service_id release_id]
      id_labels.each do |key|
        label_value = labels["com.opanel.#{key}"]
        next if label_value.nil?

        # External IDs are prefix_ulid format (e.g., tm_01ARZ3NDEKTSV4RRFFQ...)
        # ULIDs use Crockford Base32 (uppercase, no I/L/O/U)
        expect(label_value).to match(/\A[a-z]+_[0-9A-HJKMNP-TV-Z]{26}\z/)
      end
    end
  end

  describe "edge cases" do
    it "returns empty object for resource without team" do
      # Should not happen in the platform, but defensive.
      orphan = double("OrphanResource")
      allow(orphan).to receive(:respond_to?).and_return(false)

      labels = Opanel::Ownership.labels_for(orphan)
      # Just the managed=true label.
      expect(labels).to eq({ "com.opanel.managed" => "true" })
    end

    it "omits nil IDs from the label set" do
      # Create a minimal test object with nil fields
      class MinimalResource
        def team_id; nil; end
        def project_id; nil; end
        def environment_id; nil; end
        def desired_revision; nil; end
      end

      resource = MinimalResource.new

      labels = Opanel::Ownership.labels_for(resource)
      # Only managed=true, no nil labels in the output
      expect(labels["com.opanel.managed"]).to eq("true")
      expect(labels["com.opanel.team_id"]).to be_nil
      expect(labels["com.opanel.project_id"]).to be_nil
      expect(labels["com.opanel.environment_id"]).to be_nil
      expect(labels["com.opanel.desired_revision"]).to be_nil
    end
  end
end
