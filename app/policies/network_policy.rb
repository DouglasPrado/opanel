# Authorization Policy for Network resources (M01-17, doc 04 §6).
#
# Networks are scoped to their Environment's Team. Authorization follows the
# same matrix as Services: viewing requires VIEWER role, creating/updating requires
# DEVELOPER role at the team level.
#
class NetworkPolicy < ApplicationPolicy
  PERMISSIONS = {
    view: TeamPolicy::PERMISSIONS.fetch(:view),
    create: TeamPolicy::PERMISSIONS.fetch(:create_project),
    update: TeamPolicy::PERMISSIONS.fetch(:create_project)
  }.freeze

  def self.permissions = PERMISSIONS

  def view? = decide(:view).allowed?
  def create? = decide(:create).allowed?
  def update? = decide(:update).allowed?

  private

  def team = resource.is_a?(Network) ? resource.team : nil
end
