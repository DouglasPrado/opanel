require "rails_helper"

# Revision tracking: desired increments with meaningful changes, applied tracks
# what the reconciler has caught up to (doc 09 §17).
RSpec.describe Environment, "revision tracking" do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }

  describe "default values" do
    it "starts with desired_revision = 1" do
      env = create(:environment, project: project, cluster: cluster)
      expect(env.desired_revision).to eq(1)
    end

    it "starts with applied_revision = nil (until M01-18)" do
      env = create(:environment, project: project, cluster: cluster)
      expect(env.applied_revision).to be_nil
    end
  end

  describe "applied_revision state machine" do
    it "allows applied_revision to be nil" do
      env = create(:environment, project: project, cluster: cluster, applied_revision: nil)
      expect(env.applied_revision).to be_nil
    end

    it "allows applied_revision = desired_revision" do
      env = create(:environment, project: project, cluster: cluster,
        desired_revision: 5, applied_revision: 5)
      expect(env.applied_revision).to eq(5)
    end

    it "allows applied_revision < desired_revision" do
      env = create(:environment, project: project, cluster: cluster,
        desired_revision: 5, applied_revision: 3)
      expect(env.applied_revision).to eq(3)
    end

    it "forbids applied_revision > desired_revision at the database level" do
      expect {
        Environment.create!(
          project: project, cluster: cluster, team: team,
          name: "Test", slug: "test", type: "DEVELOPMENT",
          desired_revision: 5, applied_revision: 6
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /environments_applied_revision_not_ahead/)
    end
  end

  describe "auto_promote_secrets default for PRODUCTION" do
    it "defaults to false in PRODUCTION" do
      env = create(:environment, project: project, cluster: cluster, type: "PRODUCTION")
      expect(env.auto_promote_secrets).to be false
    end

    it "defaults to false in all types" do
      %w[PRODUCTION HOMOLOGATION DEVELOPMENT PREVIEW CUSTOM].each do |env_type|
        env = create(:environment, project: project, cluster: cluster, type: env_type)
        expect(env.auto_promote_secrets).to be false
      end
    end

    it "forbids true in PRODUCTION at the database level" do
      expect {
        Environment.create!(
          project: project, cluster: cluster, team: team,
          name: "Test", slug: "test", type: "PRODUCTION",
          auto_promote_secrets: true
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /environments_production_no_auto_promote/)
    end

    it "allows true in DEVELOPMENT" do
      env = create(:environment, project: project, cluster: cluster, type: "DEVELOPMENT",
        auto_promote_secrets: true)
      expect(env.auto_promote_secrets).to be true
    end
  end
end
