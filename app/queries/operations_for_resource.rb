# Fetch Operations for a specific resource, scoped and paginated.
#
# Returns all Operations that reference a given resource (e.g., a Service),
# ordered by recency. Only returns Operations for Teams the actor belongs to.
#
class OperationsForResource
  def self.call(actor:, resource_type:, resource_id:, cursor: nil, limit: 20)
    new(actor: actor, resource_type: resource_type, resource_id: resource_id, cursor: cursor, limit: limit).call
  end

  def initialize(actor:, resource_type:, resource_id:, cursor: nil, limit: 20)
    @actor = actor
    @resource_type = resource_type
    @resource_id = resource_id
    @cursor = cursor
    @limit = (limit || 20).to_i.clamp(1, 100)
  end

  def call
    # Fetch the resource to determine its owning Team.
    resource = case @resource_type
    when "Service"
      TenantScope.for(@actor, Service).find(@resource_id)
    else
      return Opanel::Result.failure(code: "NOT_FOUND", message: "Unknown resource type")
    end

    return Opanel::Result.failure(code: "NOT_FOUND", message: "Resource not found") if resource.nil?

    # Authorization: the resource must belong to a Team the actor is part of.
    team = TenantScope.for(@actor, Team).relation.find_by(id: resource.team_id)
    return Opanel::Result.failure(code: "FORBIDDEN", message: "Not authorized") if team.nil?

    # Fetch operations, ordered by recency.
    query = Operation.where(resource_type: @resource_type, resource_id: @resource_id, team_id: team.id)
      .order(created_at: :desc)

    # Pagination (cursor-based, keyed by created_at).
    if @cursor
      cursor_time = Time.iso8601(@cursor)
      query = query.where("created_at < ?", cursor_time)
    end

    entries = query.limit(@limit + 1).to_a
    has_next = entries.size > @limit
    entries = entries.first(@limit)

    next_cursor = entries.last&.created_at&.iso8601 if has_next

    Opanel::Result.success(
      operations: entries,
      next_cursor: next_cursor,
      has_next: has_next
    )
  rescue StandardError => e
    Rails.logger.error("Error fetching operations: #{e.message}")
    Opanel::Result.failure(code: "INTERNAL_ERROR", message: "Failed to fetch operations")
  end
end
