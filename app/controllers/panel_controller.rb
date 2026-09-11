# The sections of doc 10 §3.2 that exist in M01.
#
# Each action renders a page inside the app shell. The remaining two are
# deliberately placeholders — Audit's UI arrives with M11-11 — and they render
# the *empty* state rather than a blank page, because
# doc 10 §25 treats an empty state as a required state and because a shell with
# dead links teaches the user that the navigation lies.
#
# The Team comes from the URL and is resolved through `TenantScope`: a slug
# belonging to another Team is answered as absent, never as forbidden
# (Annex C §7.3). `ProjectsController` inherits that resolution rather than
# repeating it — a tenancy check written twice is a tenancy check that will be
# corrected once.
class PanelController < ApplicationController
  before_action :require_team

  def audit = render_section("Panel/Audit")
  def settings = render_section("Panel/Settings")

  protected

  attr_reader :team

  private

  def render_section(component)
    render inertia: component, props: { team: { id: team.external_id, name: team.name, slug: team.slug } }
  end

  def require_team
    @team = TenantScope.for(current_user, Team).relation.find_by(slug: params[:team_slug])

    raise ActiveRecord::RecordNotFound if @team.nil?
  end
end
