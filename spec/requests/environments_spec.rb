require "rails_helper"

# Environment CRUD routes (M01-11).
RSpec.describe "Environments", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }

  before do
    https!
    post sign_in_path, params: { email: owner.email, password: password }
  end

  describe "POST /t/:team_slug/projects/:project_id/environments" do
    it "creates an environment with valid params" do
      expect {
        post panel_project_environments_path(team_slug: team.slug, project_id: project.external_id),
          params: {
            environment: {
              name: "Production",
              slug: "prod",
              cluster_id: cluster.external_id,
              type: "PRODUCTION"
            }
          }
      }.to change(Environment, :count).by(1)

      expect(response).to redirect_to(panel_project_environment_path(team_slug: team.slug,
project_id: project.external_id, id: Environment.last.external_id))
    end

    it "rejects a duplicate slug" do
      create(:environment, project: project, cluster: cluster, slug: "prod")

      post panel_project_environments_path(team_slug: team.slug, project_id: project.external_id),
        params: {
          environment: {
            name: "Production",
            slug: "prod",
            cluster_id: cluster.external_id
          }
        }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("already used")
    end

    it "denies a VIEWER" do
      viewer = create(:user)
      create(:team_member, :viewer, team: team, user: viewer)

      post sign_out_path
      https!
      post sign_in_path, params: { email: viewer.email, password: password }

      post panel_project_environments_path(team_slug: team.slug, project_id: project.external_id),
        params: {
          environment: {
            name: "Production",
            slug: "prod",
            cluster_id: cluster.external_id
          }
        }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /t/:team_slug/projects/:project_id/environments/:id" do
    let(:environment) { create(:environment, project: project, cluster: cluster) }

    it "shows the environment" do
      get panel_project_environment_path(team_slug: team.slug, project_id: project.external_id,
id: environment.external_id)

      expect(response).to have_http_status(:ok)
    end

    it "grants access to a VIEWER" do
      viewer = create(:user)
      create(:team_member, :viewer, team: team, user: viewer)

      post sign_out_path
      https!
      post sign_in_path, params: { email: viewer.email, password: password }

      get panel_project_environment_path(team_slug: team.slug, project_id: project.external_id,
id: environment.external_id)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /t/:team_slug/projects/:project_id/environments/:id" do
    let(:environment) { create(:environment, project: project, cluster: cluster) }

    it "updates the environment name" do
      path = panel_project_environment_path(team_slug: team.slug, project_id: project.external_id,
                                            id: environment.external_id)
      patch path, params: { environment: { name: "Updated Name" } }

      expect(response).to redirect_to(path)
      expect(environment.reload.name).to eq("Updated Name")
    end

    it "denies a VIEWER" do
      viewer = create(:user)
      create(:team_member, :viewer, team: team, user: viewer)

      post sign_out_path
      https!
      post sign_in_path, params: { email: viewer.email, password: password }

      path = panel_project_environment_path(team_slug: team.slug, project_id: project.external_id,
                                            id: environment.external_id)
      patch path, params: { environment: { name: "Updated" } }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
