# Authorization for a Service that exists, against the matrix of doc 04 §6.2.
#
# Like `EnvironmentPolicy`, this answers about a resource inside a Team, and the
# Policy resolves the actor's membership from the resource's Team (the Service's).
class ServicePolicy < ApplicationPolicy
  PERMISSIONS = {
    # VIEWER may read, DEVELOPER may also create/modify.
    view: TeamPolicy::PERMISSIONS.fetch(:view),

    # Creating a Service is restricted to ADMIN and DEVELOPER. The row of
    # doc 04 §6.2 that governs it is `create_project`, the same one that governs
    # creating Projects and Environments — Services are first-class entities but live inside
    # Environments.
    create: TeamPolicy::PERMISSIONS.fetch(:create_project),

    # Updating a Service (desired state) has the same restriction as creation.
    update: TeamPolicy::PERMISSIONS.fetch(:create_project)
  }.freeze

  def self.permissions = PERMISSIONS

  # Written out rather than generated (see `ProjectPolicy` for why).
  def view? = decide(:view).allowed?
  def create? = decide(:create).allowed?
  def update? = decide(:update).allowed?

  private

  def team = resource.is_a?(Service) ? resource.team : nil
end
