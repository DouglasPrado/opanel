# Fetch an Operation by ID, scoped to the actor's Team (authorization).
#
# The Operation belongs to a Team. An actor can only see Operations for Teams
# they are a member of.
#
class OperationById
  def self.call(actor:, operation_id:, team_id: nil)
    new(actor: actor, operation_id: operation_id, team_id: team_id).call
  end

  def initialize(actor:, operation_id:, team_id: nil)
    @actor = actor
    @operation_id = operation_id
    @team_id = team_id
  end

  def call
    # If team_id was passed, validate it's one the actor belongs to.
    if @team_id
      team = TenantScope.for(@actor, Team).find_by_external_id(:team, @team_id)
      return Opanel::Result.failure(code: "NOT_FOUND", message: "Team not found") if team.nil?
      team_id_to_use = team.id
    else
      # Without explicit team, infer from the operation (scoped to actor's teams).
      operation = TenantScope.for(@actor, Operation).find(@operation_id)
      return Opanel::Result.failure(code: "NOT_FOUND", message: "Operation not found") if operation.nil?
      team_id_to_use = operation.team_id
    end

    # Authorization: actor must belong to the team that owns the operation.
    team_for_auth = TenantScope.for(@actor, Team).relation.find_by(id: team_id_to_use)
    return Opanel::Result.failure(code: "FORBIDDEN", message: "Not authorized") if team_for_auth.nil?

    # Fetch the operation.
    operation = Operation.find_by(id: @operation_id, team_id: team_id_to_use)
    return Opanel::Result.failure(code: "NOT_FOUND", message: "Operation not found") if operation.nil?

    Opanel::Result.success(operation: operation)
  rescue ActiveRecord::RecordNotFound
    Opanel::Result.failure(code: "NOT_FOUND", message: "Operation not found")
  end
end
