# The sections of doc 10 §3.2 that exist in M01.
#
# Each action renders a page inside the app shell. Three of the four are
# deliberately placeholders — Projects arrives with M01-07, Clusters with M01-08,
# Audit's UI with M11-11 — and they render the *empty* state rather than a blank
# page, because doc 10 §25 treats an empty state as a required state and because
# a shell with dead links teaches the user that the navigation lies.
#
# The Team comes from the URL and is resolved through `TenantScope`: a slug
# belonging to another Team is answered as absent, never as forbidden
# (Annex C §7.3).
class PanelController < ApplicationController
  before_action :require_team

  def projects = render_section("Panel/Projects")
  def clusters = render_section("Panel/Clusters")
  def audit = render_section("Panel/Audit")
  def settings = render_section("Panel/Settings")

  private

  attr_reader :team

  def render_section(component)
    render inertia: component, props: { team: { id: team.external_id, name: team.name, slug: team.slug } }
  end

  def require_team
    @team = TenantScope.for(current_user, Team).relation.find_by(slug: params[:team_slug])

    raise ActiveRecord::RecordNotFound if @team.nil?
  end
end
