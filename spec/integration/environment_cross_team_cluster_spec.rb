require "rails_helper"

# Creating an Environment that points to another Team's Cluster is a tenant-leak
# path (AC4). The authorization must deny it without revealing that the Cluster
# exists — a "not found" and a "not authorized" must be indistinguishable to the
# caller.
RSpec.describe "environment cross-team cluster access", :integration do
  let(:team_a) { create(:team) }
  let(:team_b) { create(:team) }
  let(:project_a) { create(:project, team: team_a) }
  let(:cluster_b) { create(:cluster, team: team_b) }
  let(:user_a) { create(:user) }

  before do
    create(:team_member, :admin, team: team_a, user: user_a)
  end

  it "refuses to create an Environment pointing at a Cluster from another Team" do
    result = CreateEnvironment.call(
      actor: user_a,
      project: project_a,
      cluster_id: cluster_b.external_id,
      name: "Prod",
      slug: "prod",
      type: "PRODUCTION"
    )

    expect(result).to be_failure
    expect(result.code).to eq("NOT_FOUND")
    expect(result.message).to match(/Cluster not found/i)
  end

  it "makes the cross-team error indistinguishable from a nonexistent cluster" do
    nonexistent_id = Opanel::Identifier.external(:cluster, Opanel::Identifier.generate)

    result_cross_team = CreateEnvironment.call(
      actor: user_a,
      project: project_a,
      cluster_id: cluster_b.external_id,
      name: "Prod",
      slug: "prod",
      type: "PRODUCTION"
    )

    result_nonexistent = CreateEnvironment.call(
      actor: user_a,
      project: project_a,
      cluster_id: nonexistent_id,
      name: "Prod",
      slug: "prod",
      type: "PRODUCTION"
    )

    # Both must be NOT_FOUND, both must have the same message shape, and the
    # response must contain nothing that reveals whether the Cluster exists.
    expect(result_cross_team.code).to eq("NOT_FOUND")
    expect(result_nonexistent.code).to eq("NOT_FOUND")
    expect(result_cross_team.message).to eq(result_nonexistent.message)
  end
end
