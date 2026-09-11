# CRUD for Services (doc 09 §5.3, doc 10 UC-013).
class ServicesController < ApplicationController
  include ErrorEnvelope

  before_action :set_environment, only: [ :index, :create ]
  before_action :set_service, only: [ :show, :update ]

  # GET /panel/projects/:project_id/environments/:environment_id/services
  def index
    page = ServicesForEnvironment.call(
      actor: current_user,
      environment: @environment,
      cursor: params[:cursor],
      limit: params[:limit]
    )

    render inertia: "Panel/Services", props: {
      team: { id: @environment.project.team.external_id, name: @environment.project.team.name,
slug: @environment.project.team.slug },
      project: { id: @environment.project.external_id, name: @environment.project.name,
slug: @environment.project.slug },
      environment: { id: @environment.external_id, name: @environment.name, slug: @environment.slug },
      services: page.entries.map do |svc|
        {
          id: svc.external_id,
          name: svc.name,
          slug: svc.slug,
          service_type: svc.service_type,
          image_ref: svc.image_ref,
          replicas: svc.replicas,
          status: svc.status,
          desired_revision: svc.desired_revision,
          created_at: svc.created_at&.iso8601
        }
      end,
      permissions: {
        create: ServicePolicy.new(current_user,
          Service.new(environment: @environment, team: @environment.team)).create?
      },
      next_cursor: page.next_cursor
    }
  end

  # POST /panel/projects/:project_id/environments/:environment_id/services
  def create
    result = CreateService.call(
      actor: current_user,
      environment: @environment,
      name: params.dig(:service, :name),
      slug: params.dig(:service, :slug),
      image_ref: params.dig(:service, :image_ref),
      service_type: params.dig(:service, :service_type) || "WEB",
      replicas: params.dig(:service, :replicas) || 1,
      ports: params.dig(:service, :ports),
      health_check: params.dig(:service, :health_check),
      cpu_reservation: params.dig(:service, :cpu_reservation),
      cpu_limit: params.dig(:service, :cpu_limit),
      memory_reservation: params.dig(:service, :memory_reservation),
      memory_limit: params.dig(:service, :memory_limit),
      constraints: params.dig(:service, :constraints)
    )

    if result.success?
      redirect_to_service_overview(result.value[:service])
    else
      render_error_response(result)
    end
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  # GET /panel/projects/:project_id/environments/:environment_id/services/:id
  def show
    raise Opanel::Authorization::Denied.new unless ServicePolicy.new(current_user, @service).view?

    overview = ServiceRuntimeView.call(actor: current_user, service: @service)

    unless overview.success?
      return render_error_response(overview)
    end

    render inertia: "Panel/Service", props: {
      team: { id: @service.environment.project.team.external_id, name: @service.environment.project.team.name,
slug: @service.environment.project.team.slug },
      project: { id: @service.environment.project.external_id, name: @service.environment.project.name,
slug: @service.environment.project.slug },
      environment: { id: @service.environment.external_id, name: @service.environment.name,
slug: @service.environment.slug },
      service: overview.value
    }
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  # PATCH /panel/projects/:project_id/environments/:environment_id/services/:id
  def update
    result = UpdateServiceDesiredState.call(
      actor: current_user,
      service: @service,
      expected_revision: params.dig(:service, :expected_revision),
      replicas: params.dig(:service, :replicas),
      image_ref: params.dig(:service, :image_ref),
      ports: params.dig(:service, :ports),
      health_check: params.dig(:service, :health_check),
      cpu_reservation: params.dig(:service, :cpu_reservation),
      cpu_limit: params.dig(:service, :cpu_limit),
      memory_reservation: params.dig(:service, :memory_reservation),
      memory_limit: params.dig(:service, :memory_limit),
      constraints: params.dig(:service, :constraints)
    )

    if result.success?
      service = result.value[:service]
      operation_id = result.value[:operation_id]

      # AC3: Return operationId for async tracking if an Operation was created.
      redirect_to panel_project_environment_service_path(
        team_slug: service.environment.project.team.slug,
        project_id: service.environment.project.external_id,
        environment_id: service.environment.external_id,
        id: service.external_id,
        operation_id: operation_id
      )
    else
      render_error_response(result)
    end
  rescue Opanel::Authorization::Denied => e
    render_authorization_error(e)
  end

  private

  def set_environment
    project = TenantScope.for(current_user, Project).find_by_external_id(:project, params[:project_id])
    return render_not_found unless project

    environment_id = Opanel::Identifier.parse(:environment, params[:environment_id])
    @environment = TenantScope.for(current_user, Environment).relation.find_by(project_id: project.id,
      id: environment_id)
    render_not_found unless @environment
  rescue Opanel::Identifier::InvalidIdentifier
    render_not_found
  end

  def set_service
    project = TenantScope.for(current_user, Project).find_by_external_id(:project, params[:project_id])
    return render_not_found unless project

    environment_id = Opanel::Identifier.parse(:environment, params[:environment_id])
    environment = TenantScope.for(current_user, Environment).relation.find_by(project_id: project.id,
      id: environment_id)
    return render_not_found unless environment

    service_id = Opanel::Identifier.parse(:service, params[:id])
    @service = TenantScope.for(current_user, Service).relation.find_by(environment_id: environment.id,
      id: service_id)
    render_not_found unless @service
  rescue Opanel::Identifier::InvalidIdentifier
    render_not_found
  end

  def redirect_to_service_overview(service)
    redirect_to panel_project_environment_service_path(
      team_slug: service.environment.project.team.slug,
      project_id: service.environment.project.external_id,
      environment_id: service.environment.external_id,
      id: service.external_id
    )
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_error_response(result)
    status = error_status(result)
    render json: error_envelope(result), status: status
  end

  def render_authorization_error(error)
    render json: { error: "Unauthorized" }, status: :forbidden
  end
end
