# Authorization for an Environment that exists, against the matrix of doc 04 §6.2.
#
# Like `ProjectPolicy`, this answers about a resource inside a Team, and the
# Policy resolves the actor's membership from the resource's Team (the Environment's).
class EnvironmentPolicy < ApplicationPolicy
  PERMISSIONS = {
    # VIEWER may read, DEVELOPER may also create/modify.
    view: TeamPolicy::PERMISSIONS.fetch(:view),

    # Creating an Environment is restricted to ADMIN and DEVELOPER. The row of
    # doc 04 §6.2 that governs it is `create_project`, the same one that governs
    # creating Projects — Environments are first-class entities but live inside
    # Projects.
    create: TeamPolicy::PERMISSIONS.fetch(:create_project),

    # Updating an Environment (name, slug in M01) has the same restriction as
    # creation: ADMIN and DEVELOPER.
    update: TeamPolicy::PERMISSIONS.fetch(:create_project)
  }.freeze

  def self.permissions = PERMISSIONS

  # Written out rather than generated (see `ProjectPolicy` for why).
  def view? = decide(:view).allowed?
  def create? = decide(:create).allowed?
  def update? = decide(:update).allowed?

  private

  def team = resource.is_a?(Environment) ? resource.team : nil
end
