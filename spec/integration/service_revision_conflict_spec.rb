require "rails_helper"

# AC4: Optimistic concurrency control — expectedRevision prevents lost updates.
#
# Expected_revision checking is a regular transactional test. Concurrent updates
# require a barrier to force the exact interleaving that exposes the race, so
# those live in a separate `:concurrent` group.
RSpec.describe "service revision conflict", :integration do
  before(:each) do
    FactoryBot.rewind_sequences
    # Clear any orphaned users that weren't cleaned up by previous tests
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment, replicas: 1) }
  let(:actor) { create(:user) }
  let!(:tm) { create(:team_member, team: team, user: actor, role: "DEVELOPER") }

  def update_service(actor:, service:, expected_revision:, replicas:)
    UpdateServiceDesiredState.call(
      actor: actor, service: service, expected_revision: expected_revision,
      replicas: replicas
    )
  end

  describe "expected_revision checking" do
    it "accepts an update when expected_revision matches" do
      result = update_service(actor: actor, service: service,
        expected_revision: 1, replicas: 3)

      expect(result.success?).to be(true)
      expect(service.reload.replicas).to eq(3)
    end

    it "rejects an update with a stale expected_revision" do
      # Bump to revision 2.
      update_service(actor: actor, service: service,
        expected_revision: 1, replicas: 2)

      # Try to update with old expected_revision; must fail.
      result = update_service(actor: actor, service: service,
        expected_revision: 1, replicas: 3)

      expect(result.success?).to be false
      expect(result.code).to eq("REVISION_CONFLICT")
      expect(service.reload.replicas).to eq(2)  # Did not change
    end

    it "succeeds with the current expected_revision" do
      # Bump to revision 2.
      update_service(actor: actor, service: service,
        expected_revision: 1, replicas: 2)

      # Update with the correct expected_revision.
      result = update_service(actor: actor, service: service,
        expected_revision: 2, replicas: 3)

      expect(result.success?).to be(true)
      expect(service.reload.replicas).to eq(3)
      expect(service.desired_revision).to eq(3)
    end
  end

  describe "when expected_revision is not provided" do
    it "allows the update without a conflict check (assumed trusted)" do
      # UpdateServiceDesiredState allows nil expected_revision for non-critical paths.
      result = update_service(actor: actor, service: service,
        expected_revision: nil, replicas: 5)

      expect(result.success?).to be(true)
      expect(service.reload.replicas).to eq(5)
    end
  end
end
