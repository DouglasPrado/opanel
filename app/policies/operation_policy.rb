# Authorization for Operations (doc 04 §5, Opanel::Authorization).
#
# An Operation belongs to a Team. An actor may view Operations only
# for Teams they are a member of, with role-based permissions.
#
class OperationPolicy < ApplicationPolicy
  PERMISSIONS = {
    # VIEWER may read Operations.
    view: TeamPolicy::PERMISSIONS.fetch(:view)
  }.freeze

  def self.permissions = PERMISSIONS

  def view? = decide(:view).allowed?

  private

  def team = resource.is_a?(Operation) ? resource.team : nil
end
