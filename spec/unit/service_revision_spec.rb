require "rails_helper"

# Revision tracking: desired increments with meaningful changes, applied tracks
# what the reconciler has caught up to (doc 09 §17).
RSpec.describe Service, "revision tracking" do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }

  describe "default values" do
    it "starts with desired_revision = 1" do
      svc = create(:service, environment: environment)
      expect(svc.desired_revision).to eq(1)
    end

    it "starts with applied_revision = nil (until M01-18)" do
      svc = create(:service, environment: environment)
      expect(svc.applied_revision).to be_nil
    end
  end

  describe "applied_revision state machine" do
    it "allows applied_revision to be nil" do
      svc = create(:service, environment: environment, applied_revision: nil)
      expect(svc.applied_revision).to be_nil
    end

    it "allows applied_revision = desired_revision" do
      svc = create(:service, environment: environment,
        desired_revision: 5, applied_revision: 5)
      expect(svc.applied_revision).to eq(5)
    end

    it "allows applied_revision < desired_revision" do
      svc = create(:service, environment: environment,
        desired_revision: 5, applied_revision: 3)
      expect(svc.applied_revision).to eq(3)
    end

    it "forbids applied_revision > desired_revision at the database level" do
      expect {
        Service.create!(
          environment: environment, team: team,
          name: "Test", slug: "test", service_type: "WEB",
          image_ref: "nginx:latest", replicas: 1,
          status: "DRAFT",
          desired_revision: 5, applied_revision: 6,
          technical_name: "test-service"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /services_applied_revision_not_ahead/)
    end
  end
end
