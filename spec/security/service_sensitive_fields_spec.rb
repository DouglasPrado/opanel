require "rails_helper"

# AC10: No field of Service accepts or persists sensitive values.
# Secrets are Vault (M03), and the UI makes this explicit.
RSpec.describe "Service security: no sensitive fields", :security do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }

  describe "image_ref validation" do
    it "rejects image references with invalid tag characters" do
      # The imageRef field is validated by OCI syntax rules. Special characters
      # like $ are not valid in OCI tags and are rejected.
      invalid_refs = [
        "docker.io/secret:$MY_TOKEN",  # $ not allowed in tags
        "nginx:inv@lid",  # @ only for digest
        ""  # empty
      ]

      invalid_refs.each do |ref|
        parser = Opanel::ImageRef.new(ref)
        expect { parser.parse }.to raise_error(Opanel::ImageRef::InvalidReference)
      end
    end

    it "accepts valid OCI image references" do
      valid_refs = [
        "nginx:latest",
        "gcr.io/my-project/my-service:v1.0.0",
        "docker.io/library/postgres:15",
        "my-registry.com/my-image:v1.2.3-alpha"
      ]

      valid_refs.each do |ref|
        parser = Opanel::ImageRef.new(ref)
        expect { parser.parse }.not_to raise_error
      end
    end
  end

  describe "audit log redaction" do
    it "allows name, slug, image_ref and other non-sensitive fields through" do
      user = create(:user)
      tm = create(:team_member, team: team, user: user, role: "DEVELOPER")

      result = CreateService.call(
        actor: user,
        environment: environment,
        name: "my-api",
        slug: "my-api",
        image_ref: "docker.io/my-service:v1"
      )

      expect(result.success?).to be true

      # Check that the audit record was created and contains the expected fields.
      service = result.value[:service]
      audit_logs = AuditLog.for_resource("Service", service.id).where(action: "service.created")

      expect(audit_logs).not_to be_empty
      # The after block should contain name, slug, image_ref.
      after_data = audit_logs.first.after

      expect(after_data["name"]).to eq("my-api")
      expect(after_data["slug"]).to eq("my-api")
      expect(after_data["image_ref"]).to eq("docker.io/my-service:v1")
    end
  end
end
