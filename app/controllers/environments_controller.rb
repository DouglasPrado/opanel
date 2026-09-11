# CRUD for Environments (doc 09 §5.2, doc 10 UC-010).
class EnvironmentsController < ApplicationController
  before_action :set_project, only: [ :index, :create ]
  before_action :set_environment, only: [ :show, :update ]

  # GET /panel/projects/:project_id/environments
  def index
    page = EnvironmentsForProject.call(
      actor: current_user,
      project: @project,
      cursor: params[:cursor],
      limit: params[:limit]
    )

    clusters = Cluster.accessible_to(current_user).where(team: @project.team).map do |c|
      { id: c.external_id, name: c.name, slug: c.slug }
    end

    render inertia: "Panel/Environments", props: {
      team: { id: @project.team.external_id, name: @project.team.name, slug: @project.team.slug },
      project: { id: @project.external_id, name: @project.name, slug: @project.slug },
      environments: page.entries.map do |env|
        {
          id: env.id,
          name: env.name,
          slug: env.slug,
          type: env.type,
          status: env.status,
          clusterName: "(Loading)",
          createdAt: env.created_at&.iso8601
        }
      end,
      clusters: clusters,
      permissions: { create: EnvironmentPolicy.new(current_user,
Environment.new(project: @project, team: @project.team)).create? }
    }
  end

  # POST /panel/projects/:project_id/environments
  def create
    result = CreateEnvironment.call(
      actor: current_user,
      project: @project,
      cluster_id: params.dig(:environment, :cluster_id),
      name: params.dig(:environment, :name),
      slug: params.dig(:environment, :slug),
      type: params.dig(:environment, :type) || "DEVELOPMENT"
    )

    if result.success?
      redirect_to_environment_overview(result.value[:environment])
    else
      render_error_response(result)
    end
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  # GET /panel/projects/:project_id/environments/:id
  def show
    raise Opanel::Authorization::Denied.new unless EnvironmentPolicy.new(current_user, @environment).view?

    overview = EnvironmentOverview.call(actor: current_user, environment: @environment)
    render inertia: "Panel/Environment", props: {
      team: { id: @environment.project.team.external_id, name: @environment.project.team.name,
slug: @environment.project.team.slug },
      project: { id: @environment.project.external_id, name: @environment.project.name,
slug: @environment.project.slug },
      environment: {
        id: @environment.id,
        name: @environment.name,
        slug: @environment.slug,
        type: @environment.type,
        status: @environment.status,
        clusterName: @environment.cluster&.name || "(Unknown)",
        createdAt: @environment.created_at&.iso8601
      }
    }
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  # PATCH /panel/projects/:project_id/environments/:id
  def update
    result = UpdateEnvironment.call(
      actor: current_user,
      environment: @environment,
      name: params.dig(:environment, :name),
      slug: params.dig(:environment, :slug)
    )

    if result.success?
      redirect_to_environment_overview(result.value[:environment])
    else
      render_error_response(result)
    end
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  private

  def set_project
    @project = TenantScope.for(current_user, Project).find_by_external_id(:project, params[:project_id])
    render_not_found unless @project
  end

  def set_environment
    project = TenantScope.for(current_user, Project).find_by_external_id(:project, params[:project_id])
    return render_not_found unless project

    environment_id = Opanel::Identifier.parse(:environment, params[:id])
    @environment = TenantScope.for(current_user, Environment).relation.find_by(project_id: project.id,
id: environment_id)
    render_not_found unless @environment
  rescue Opanel::Identifier::InvalidIdentifier
    render_not_found
  end

  def redirect_to_environment_overview(environment)
    redirect_to panel_project_environment_path(
      team_slug: environment.project.team.slug,
      project_id: environment.project.external_id,
      id: environment.external_id
    )
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_error_response(result)
    status = result.code == "CONFLICT" ? :forbidden : :unprocessable_entity
    render json: { error: result.message, details: result.details }, status: status
  end

  def render_authorization_error(error)
    render json: { error: "Unauthorized" }, status: :forbidden
  end
end
