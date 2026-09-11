# Authorization for ServiceObservation (actual state observations).
#
# ServiceObservation is append-only, immutable, and read-only. A user can view
# an observation if and only if they can view the parent Service. Authorization
# is tenancy-scoped through Service → Environment → Project → Team.
class ServiceObservationPolicy < ApplicationPolicy
  def view?
    # User can view observation only if they can view the Service.
    return false if resource.nil? || resource.service.nil?

    ServicePolicy.new(actor, resource.service).view?
  end

  alias_method :read?, :view?
end
