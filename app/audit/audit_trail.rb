# The one call a Command makes to leave a trail.
#
#   AuditTrail.record(action: :team_created, actor: actor, resource: team,
#                     result: "SUCCESS", after: team.attributes)
#
# It exists because the alternative — every Command assembling its own record — is
# how correlation fields go missing and how an unsanitised attribute reaches the
# row. Here `request_id` and `correlation_id` come from `Current` and cannot be
# forgotten, and `before`/`after` go through the allowlist whether the caller
# thought about it or not.
#
# ## Inside the caller's transaction, on purpose
#
# `record` opens nothing. The Story is explicit: *"Falha ao gravar AuditLog em ação
# crítica → a mutação **não** é considerada bem-sucedida; audit e mutação
# compartilham a transação"* (AC11). A Command that calls this inside its
# transaction gets exactly that — a failed insert takes the mutation with it. A
# Command that calls it outside gets a trail that can lag reality, which is a
# choice it makes visibly rather than one this class makes for everybody.
class AuditTrail
  # A non-user actor. Symbols rather than strings so a request parameter can
  # never impersonate one (the same reasoning as `SuspendTeamMember::SECURITY_PROCEDURE`).
  SYSTEM = :system
  RECOVERY = :recovery

  class << self
    def record(action:, actor:, resource:, result: "SUCCESS", team: nil,
      before: nil, after: nil, operation_id: nil, ip: nil, user_agent: nil)
      name = AuditLog::ACTIONS.fetch(action) do
        raise ArgumentError, "#{action.inspect} is not a registered audit action. " \
          "Add it to AuditLog::ACTIONS — an unnamed action makes the trail unfilterable."
      end

      resource_type = resource_type_for(resource)

      AuditLog.create!(
        team_id: (team || team_of(resource))&.id,
        actor_type: actor_type_for(actor),
        actor_id: actor_id_for(actor),
        action: name,
        resource_type: resource_type,
        resource_id: resource.try(:id),
        request_id: Current.request_id.presence || Current.correlation_id,
        correlation_id: Current.correlation_id,
        operation_id: operation_id,
        ip: ip,
        user_agent: user_agent,
        before: AuditSanitizer.call(resource_type, before),
        after: AuditSanitizer.call(resource_type, after),
        result: result,
        created_at: Time.current
      )
    end

    private

    def resource_type_for(resource)
      return resource.to_s if resource.is_a?(Symbol) || resource.is_a?(String)

      resource.class.name
    end

    def actor_type_for(actor)
      case actor
      when SYSTEM then "SYSTEM"
      when RECOVERY then "RECOVERY"
      when nil then "SYSTEM"
      else actor.is_a?(User) ? "USER" : "SYSTEM"
      end
    end

    def actor_id_for(actor)
      actor.is_a?(User) ? actor.id : nil
    end

    # Every tenant-scoped resource has an unambiguous path to its Team
    # (doc 09 §30). Resolving it here keeps `team_id` from depending on each
    # caller remembering to pass it.
    def team_of(resource)
      return resource if resource.is_a?(Team)
      return resource.team if resource.respond_to?(:team)

      nil
    end
  end
end
