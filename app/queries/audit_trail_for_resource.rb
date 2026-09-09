# The trail of one resource, and the chain of one request.
#
# Two reads that answer the two questions an incident actually asks — *"what
# happened to this thing?"* and *"what did this request do?"* — and each one is
# served by an index the migration declares, so neither degrades into a scan as
# the table grows past the floors of Annex B §9.1.
#
# The UI for this is M11-11. What exists here is the query it will use, because
# an index nobody exercises is an index nobody knows is wrong.
class AuditTrailForResource
  LIMIT = 200

  def self.for_resource(resource, limit: LIMIT)
    new.for_resource(resource, limit: limit)
  end

  def self.for_request(request_id, limit: LIMIT)
    new.for_request(request_id, limit: limit)
  end

  # Newest first: an operator reading a trail starts from what just happened.
  # Uses `index_audit_logs_on_resource_and_created_at`.
  def for_resource(resource, limit: LIMIT)
    AuditLog.for_resource(resource.class.name, resource.id).limit(limit)
  end

  # AC8: from one request id, the whole chain in the order it happened. Uses
  # `index_audit_logs_on_request_id`. Ascending here, deliberately — a chain reads
  # forwards, unlike a trail.
  def for_request(request_id, limit: LIMIT)
    AuditLog.for_request(request_id).limit(limit)
  end

  # Everything a Team may see of its own history. Uses
  # `index_audit_logs_on_team_id_and_created_at`.
  #
  # Scoped through `TenantScope`'s boundary rather than by `team_id` alone: the
  # caller passes an actor, not a Team id, so this cannot be handed a Team the
  # actor has no membership of.
  def for_team(actor, team, limit: LIMIT)
    reachable = TenantScope.for(actor, Team).find(team.id)
    return AuditLog.none if reachable.nil?

    AuditLog.where(team_id: reachable.id).order(created_at: :desc).limit(limit)
  end
end
