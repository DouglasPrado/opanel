# Creating a Team and reading one (AC1, AC8).
#
# Deliberately three actions. Members, invitations, roles and the product UI of a
# Team belong to later Stories (M11-01, M01-22); what exists here is the surface
# the Story's acceptance criteria need — a Team can be created by the person
# signed in, and a Team can be opened only while their membership is ACTIVE.
#
# Inertia serves both pages and there is no REST endpoint behind them. The public
# API of later Milestones will call `CreateTeam` and `TeamsForUser`, not a second
# copy of their rules.
class TeamsController < ApplicationController
  include ErrorEnvelope

  INDEX_PAGE = "Teams/Index"
  SHOW_PAGE = "Teams/Show"

  def index
    render inertia: INDEX_PAGE, props: index_props
  end

  def create
    result = CreateTeam.call(actor: current_user, name: submitted[:name], slug: submitted[:slug])

    if result.failure?
      return render inertia: INDEX_PAGE,
        props: index_props.merge(error: error_envelope(result), suggestion: result.details[:suggestion]),
        status: error_status(result)
    end

    redirect_to team_path(result.value.fetch(:team).external_id)
  end

  # The Team is fetched **through the membership**, never by id with a check
  # afterwards (Annex C §7.3). A caller whose membership was suspended gets the
  # same answer as one asking about a Team that does not exist: 404, not 403.
  # 403 would confirm the Team exists to somebody who has just lost access to it.
  def show
    # Through the tenancy helper rather than by id: a Team of another Team's owner
    # is answered as absent, not as forbidden (Annex C §7.3, AC4).
    team = TenantScope.for(current_user, Team).find(team_id)

    raise ActiveRecord::RecordNotFound if team.nil?

    render inertia: SHOW_PAGE, props: { team: team_prop(team) }
  end

  private

  def team_id
    Opanel::Identifier.parse(:team, params[:id])
  rescue Opanel::Identifier::InvalidIdentifier
    # A malformed identifier cannot match a row, and answering 404 keeps this
    # action from telling an enumerator which shapes are real.
    nil
  end

  def index_props
    { teams: TeamsForUser.call(user: current_user).map { |entry| entry_prop(entry) } }
  end

  # Written out field by field rather than dumped from the record: what leaves
  # the server is a decision, and a list nobody wrote is a list nobody reviewed.
  def entry_prop(entry)
    {
      id: entry.id,
      name: entry.name,
      slug: entry.slug,
      role: entry.role,
      status: entry.status,
      joinedAt: entry.joined_at&.iso8601
    }
  end

  def team_prop(team)
    {
      id: team.external_id,
      name: team.name,
      slug: team.slug,
      status: team.status
    }
  end

  def submitted
    params.permit(:name, :slug)
  end
end
