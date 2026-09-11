# Projects of a Team: list, create, rename, archive (UC-009, doc 10 §7).
#
# Inherits `PanelController` for its `require_team`, which resolves the slug in
# the URL through the tenancy boundary on every request. A slug is an argument,
# not an authorization — reusing that one resolution is what keeps every action
# here from having to remember it.
#
# The rich Projects screen of doc 10 §7.1 — production status, last deploy,
# attention — is `M01-22`, and needs Environments, deployments and derived health
# to exist first. What this Story ships is the short flow of doc 10 §7.2: a name,
# a slug, and a list.
#
# Served by Inertia. There is no REST endpoint behind these pages; the public API
# of later Milestones will call the same Commands rather than a second copy of
# their rules.
class ProjectsController < PanelController
  include ErrorEnvelope

  LIST_PAGE = "Panel/Projects"
  OVERVIEW_PAGE = "Panel/Project"

  def index
    render inertia: LIST_PAGE, props: page_props
  end

  def create
    result = CreateProject.call(actor: current_user, team: team, name: submitted[:name],
      slug: submitted[:slug], description: submitted[:description])

    if result.failure?
      return render inertia: LIST_PAGE,
        props: page_props.merge(error: error_envelope(result),
          suggestion: result.details[:suggestion]),
        status: error_status(result)
    end

    # UC-009 passo 6, verbatim: *"UI abre Project Overview"*. An earlier version
    # of this action went back to the list, which is a divergence from the use
    # case this Story cites — and it left `ProjectOverview` with no caller at all.
    redirect_to panel_project_path(team_slug: team.slug,
      id: result.value.fetch(:project).external_id)
  end

  # The minimal `ProjectOverview` of doc 09 §23. Environments, aggregated health
  # and the last deployment join it in `M01-11`, `M01-19` and `M01-22`.
  def show
    render inertia: OVERVIEW_PAGE, props: overview_props(require_project)
  end

  def update
    project = require_project

    result = UpdateProject.call(actor: current_user, project: project, **update_arguments)

    if result.failure?
      return render inertia: OVERVIEW_PAGE,
        props: overview_props(project).merge(error: error_envelope(result),
          suggestion: result.details[:suggestion]),
        status: error_status(result)
    end

    redirect_to panel_project_path(team_slug: team.slug, id: project.external_id)
  end

  def archive
    project = require_project

    result = ArchiveProject.call(actor: current_user, project: project)

    if result.failure?
      return render inertia: OVERVIEW_PAGE,
        props: overview_props(project).merge(error: error_envelope(result)),
        status: error_status(result)
    end

    redirect_to panel_project_path(team_slug: team.slug, id: project.external_id)
  end

  private

  def require_project
    project = scoped_project
    raise ActiveRecord::RecordNotFound if project.nil?

    project
  end

  # Through the tenancy boundary, and never by id with a check afterwards
  # (Annex C §7.3, AC4). A Project of another Team is answered as absent, which is
  # what makes NOT_FOUND and FORBIDDEN indistinguishable across Teams.
  def scoped_project
    id = Opanel::Identifier.parse(:project, params[:id])

    TenantScope.for(current_user, Project).relation.where(team_id: team.id).find_by(id: id)
  rescue Opanel::Identifier::InvalidIdentifier
    # A malformed identifier cannot match a row, and answering 404 keeps this
    # action from telling an enumerator which shapes are real.
    nil
  end

  # `UPDATE` with only the fields the request actually sent. `UNCHANGED` is what
  # distinguishes "leave the description alone" from "clear it", and building the
  # argument list from `params.key?` is what preserves that distinction across the
  # HTTP boundary — a form that omits a field must not erase it.
  def update_arguments
    %i[name slug description].each_with_object({}) do |field, arguments|
      arguments[field] = submitted[field] if submitted.key?(field)
    end
  end

  def page_props
    page = ProjectsForTeam.call(actor: current_user, team: team, cursor: params[:cursor])

    {
      team: { id: team.external_id, name: team.name, slug: team.slug },
      projects: page.entries.map { |entry| project_prop(entry) },
      nextCursor: page.next_cursor,
      # So the interface does not offer an action the server will refuse
      # (doc 10, and the Security Requirements of `M01-22`). It is advisory: every
      # mutation is authorized again, independently, in its Command.
      permissions: { create: TeamPolicy.new(current_user, team).create_project? }
    }
  end

  # The read model, rendered field by field. The permissions come from the same
  # `ProjectPolicy` the Commands go through, so the buttons the page offers and
  # the actions the server accepts cannot disagree — and the server authorizes
  # again regardless.
  def overview_props(project)
    overview = ProjectOverview.call(actor: current_user, project: project)

    {
      team: { id: overview.team.id, name: overview.team.name, slug: overview.team.slug },
      project: {
        id: overview.id,
        name: overview.name,
        slug: overview.slug,
        description: overview.description,
        status: overview.status,
        createdAt: overview.created_at&.iso8601,
        updatedAt: overview.updated_at&.iso8601
      },
      permissions: {
        update: overview.permissions.update,
        archive: overview.permissions.archive
      }
    }
  end

  # Written out field by field rather than dumped from the record: what leaves the
  # server is a decision, and a list nobody wrote is a list nobody reviewed.
  def project_prop(entry)
    {
      id: entry.id,
      name: entry.name,
      slug: entry.slug,
      description: entry.description,
      status: entry.status,
      createdAt: entry.created_at&.iso8601
    }
  end

  def submitted
    params.permit(:name, :slug, :description)
  end
end
