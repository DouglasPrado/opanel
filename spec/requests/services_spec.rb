require "rails_helper"

# Service CRUD routes (M01-12).
RSpec.describe "Services", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let(:team) { create(:team, owner: owner) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, :bootstrapped, team: team) }
  let(:environment) { create(:environment, project: project, cluster: cluster) }

  before do
    https!
    post sign_in_path, params: { email: owner.email, password: password }
  end

  def response_json
    JSON.parse(response.body)
  end

  describe "POST /t/:team_slug/projects/:project_id/environments/:environment_id/services" do
    it "creates a service with valid params" do
      expect {
        post panel_project_environment_services_path(
          team_slug: team.slug, project_id: project.external_id, environment_id: environment.external_id
        ),
          params: {
            service: {
              name: "API",
              slug: "api",
              image_ref: "myregistry/app:v1.0",
              service_type: "WEB",
              replicas: 2
            }
          }
      }.to change(Service, :count).by(1)

      expect(response).to redirect_to(panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: Service.last.external_id
      ))
    end

    it "rejects a duplicate slug" do
      create(:service, environment: environment, slug: "api")

      post panel_project_environment_services_path(
        team_slug: team.slug, project_id: project.external_id, environment_id: environment.external_id
      ),
        params: {
          service: {
            name: "API",
            slug: "api",
            image_ref: "myregistry/app:v1.0"
          }
        }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("already used")
    end

    it "denies a VIEWER" do
      viewer = create(:user, email: "viewer@example.test")
      create(:team_member, team: team, user: viewer, role: "VIEWER")

      https!
      post sign_in_path, params: { email: viewer.email, password: password }

      post panel_project_environment_services_path(
        team_slug: team.slug, project_id: project.external_id, environment_id: environment.external_id
      ),
        params: {
          service: {
            name: "API",
            slug: "api",
            image_ref: "myregistry/app:v1.0"
          }
        }

      expect(response).to have_http_status(:forbidden)
      # Authorization errors must not disclose environment details
      expect(response.body).not_to include(environment.name)
      expect(response.body).not_to include(environment.slug)
    end

    it "denies cross-team access" do
      other_team = create(:team)
      other_project = create(:project, team: other_team)
      other_env = create(:environment, project: other_project, cluster: cluster)

      post panel_project_environment_services_path(
        team_slug: other_team.slug, project_id: other_project.external_id,
        environment_id: other_env.external_id
      ),
        params: {
          service: {
            name: "API",
            slug: "api",
            image_ref: "myregistry/app:v1.0"
          }
        }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /t/:team_slug/projects/:project_id/environments/:environment_id/services/:id" do
    let(:service) { create(:service, environment: environment) }

    it "displays the service" do
      get panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: service.external_id
      )

      expect(response).to have_http_status(:ok)
    end

    it "denies cross-team access" do
      other_team = create(:team)
      other_project = create(:project, team: other_team)
      other_env = create(:environment, project: other_project, cluster: cluster)
      other_service = create(:service, environment: other_env)

      get panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: other_service.external_id
      )

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /t/:team_slug/projects/:project_id/environments/:environment_id/services/:id" do
    let(:service) { create(:service, environment: environment, replicas: 1) }

    it "updates service desired state" do
      expect {
        patch panel_project_environment_service_path(
          team_slug: team.slug, project_id: project.external_id,
          environment_id: environment.external_id, id: service.external_id
        ),
          params: {
            service: {
              replicas: 3,
              expected_revision: service.desired_revision
            }
          }
      }.to change(Operation, :count).by(1)

      # AC3: Response returns operationId in the redirect and does not wait for runtime.
      operation = Operation.last
      expect(response).to redirect_to(panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: service.external_id,
        operation_id: operation.external_id
      ))

      expect(service.reload.replicas).to eq(3)
    end

    it "rejects a revision conflict" do
      patch panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: service.external_id
      ),
        params: {
          service: {
            replicas: 3,
            expected_revision: service.desired_revision - 1
          }
        }

      expect(response).to have_http_status(:conflict)
      expect(response_json["code"]).to eq("REVISION_CONFLICT")
      expect(service.reload.replicas).to eq(1)
    end

    it "denies cross-team access" do
      other_team = create(:team)
      other_project = create(:project, team: other_team)
      other_env = create(:environment, project: other_project, cluster: cluster)
      other_service = create(:service, environment: other_env)

      patch panel_project_environment_service_path(
        team_slug: team.slug, project_id: project.external_id,
        environment_id: environment.external_id, id: other_service.external_id
      ),
        params: {
          service: {
            replicas: 3,
            desired_revision: other_service.desired_revision
          }
        }

      expect(response).to have_http_status(:not_found)
    end
  end
end
