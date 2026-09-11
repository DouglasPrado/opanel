require "rails_helper"

# AC6: ownership labels contain no sensitive values — only opaque IDs and
# revision numbers. No names, slugs, credentials, or secrets (Annex C §7).
RSpec.describe "Ownership labels security", :security do
  before(:each) { User.delete_all }

  let(:team) { create(:team, name: "Secret Team", slug: "secret-team") }
  let(:project) { create(:project, team: team, name: "Secret Project", slug: "secret-project") }
  let(:environment) { create(:environment, project: project, name: "Secret Env", slug: "secret-env") }
  let(:service) {
 create(:service, environment: environment, name: "Secret Service", slug: "secret-svc", desired_revision: 99) }

  describe "AC6: no sensitive values in labels" do
    it "never exposes human names in Service labels" do
      labels = Opanel::Ownership.labels_for(service)

      sensitive_strings = [
        service.name,
        service.slug,
        environment.name,
        environment.slug,
        project.name,
        project.slug,
        team.name,
        team.slug
      ]

      labels.each do |key, value|
        sensitive_strings.each do |sensitive|
          expect(value).not_to include(sensitive),
            "Label #{key}=#{value} contains sensitive string '#{sensitive}'"
        end
      end
    end

    it "contains only opaque IDs in ID labels" do
      labels = Opanel::Ownership.labels_for(service)

      id_labels = {
        "com.opanel.team_id" => team,
        "com.opanel.project_id" => project,
        "com.opanel.environment_id" => environment,
        "com.opanel.service_id" => service
      }

      id_labels.each do |label_name, expected_resource|
        label_value = labels[label_name]
        next if label_value.nil?

        # Value must be an external ID (prefix_ulid), not a human name
        # ULIDs use Crockford Base32 (uppercase, no I/L/O/U)
        expect(label_value).to match(/\A[a-z]+_[0-9A-HJKMNP-TV-Z]{26}\z/),
          "#{label_name} should be an opaque external ID, got '#{label_value}'"

        # Verify it's not a slug or name
        expect(label_value).not_to include(expected_resource.slug),
          "Label value should not contain slug"
        expect(label_value).not_to include(expected_resource.name),
          "Label value should not contain name"
      end
    end

    it "exposes only the desired revision as a number, not configuration" do
      labels = Opanel::Ownership.labels_for(service)

      revision_label = labels["com.opanel.desired_revision"]
      expect(revision_label).to eq("99")

      # Just the number, no configuration details
      expect(revision_label).not_to include("replica")
      expect(revision_label).not_to include("image")
      expect(revision_label).not_to include("environment")
    end

    it "does not expose resource status or health" do
      labels = Opanel::Ownership.labels_for(service)

      # No status labels
      expect(labels).not_to have_key("com.opanel.status")
      expect(labels).not_to have_key("com.opanel.health")
      expect(labels).not_to have_key("com.opanel.state")
    end

    it "does not expose image references" do
      labels = Opanel::Ownership.labels_for(service)

      # No image digests or references
      expect(labels).not_to have_key("com.opanel.image")
      expect(labels).not_to have_key("com.opanel.image_digest")

      labels.each do |key, value|
        expect(value).not_to include("redis"),
          "Label should not expose image name"
        expect(value).not_to include("sha256:"),
          "Label should not expose digest"
      end
    end

    it "Environment labels do not expose service_id or release_id" do
      # Services that are children of this environment should not leak into its labels
      labels = Opanel::Ownership.labels_for(environment)

      # Environment owns networks, not services
      expect(labels).not_to have_key("com.opanel.service_id")
      expect(labels).not_to have_key("com.opanel.release_id")

      # Only the environment's own ID
      expect(labels).to have_key("com.opanel.environment_id")
      expect(labels["com.opanel.environment_id"]).to eq(environment.external_id)
    end
  end

  describe "log safety" do
    it "does not log label values that might contain secrets" do
      labels = Opanel::Ownership.labels_for(service)

      # If labels were logged (e.g., as part of auditing), they should be safe
      # This is a documentation test: the predicate logs anomalies. Verify no
      # label value contains patterns that look like secrets.
      labels.each do |key, value|
        expect(value).not_to match(/secret|password|token|key|credential/i),
          "Label #{key} contains a secret-like keyword"
        expect(value).not_to match(/[\*{}<>%]/),
          "Label value contains suspicious characters"
      end
    end
  end
end
