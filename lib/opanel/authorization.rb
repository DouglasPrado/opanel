# frozen_string_literal: true

module Opanel
  # `authorize(actor, action, resource)` — the entry point doc 04 §6 names, and
  # the one thing a Command calls before it mutates.
  #
  # It is a module function rather than a base class so that a Command inherits
  # nothing and a Query can use the same decision. The Policy is chosen from the
  # resource, which keeps the caller from picking the wrong one.
  #
  # Two shapes, on purpose:
  #
  #   * `authorize` returns a `Decision`, for a caller that wants to log or branch;
  #   * `authorize!` returns the resource or raises `Denied`, for the common case
  #     where a refusal ends the request.
  #
  # A denial is logged here, once, with the classified reason — so no Command can
  # deny without leaving the record the Story's Observability Requirements ask
  # for, and no Command has to remember to write it.
  module Authorization
    class Denied < StandardError
      attr_reader :decision

      def initialize(decision)
        @decision = decision
        super("#{decision.action} denied: #{ApplicationPolicy::REASONS.fetch(decision.reason)}")
      end
    end

    # Resource class -> Policy. Explicit rather than derived from the class name:
    # a resource that belongs to a Team is authorized by `TeamPolicy` whether it
    # is a Team, a membership, or later a Project, and guessing `TeamMemberPolicy`
    # from `TeamMember` would silently deny by raising `NameError` instead.
    POLICIES = {
      "Team" => "TeamPolicy",
      "TeamMember" => "TeamPolicy",
      # A Project has a Policy of its own because the decision is about a
      # resource *inside* the Team, and `ApplicationPolicy` resolves the actor's
      # membership from the resource — so the answer is scoped to this Project's
      # Team rather than to whichever Team the route named.
      "Project" => "ProjectPolicy",
      # Bootstrapping addresses a Cluster that does not exist yet, so the
      # decision is constructed with an unsaved one carrying the target Team —
      # which is what lets the dispatcher stay a map from resource class to
      # Policy instead of growing a special case.
      "Cluster" => "ClusterPolicy",
      # An Environment belongs to a Project which belongs to a Team; the Policy
      # resolves the actor's membership from the Environment's Team.
      "Environment" => "EnvironmentPolicy",
      # A Service belongs to an Environment which belongs to a Project which belongs
      # to a Team; the Policy resolves the actor's membership from the Service's Team.
      "Service" => "ServicePolicy",
      # An Operation belongs to a Team directly and records infrastructure work.
      # The Policy resolves the actor's membership from the Operation's Team.
      "Operation" => "OperationPolicy"
    }.freeze

    module_function

    def policy_for(resource)
      name = POLICIES[resource.class.name]

      raise ArgumentError, "no Policy is registered for #{resource.class.name}" if name.nil?

      name.constantize
    end

    def authorize(actor, action, resource)
      decision = policy_for(resource).new(actor, resource).decide(action)
      record(actor, decision)
      decision
    end

    def authorize!(actor, action, resource)
      decision = authorize(actor, action, resource)
      raise Denied, decision if decision.denied?

      resource
    end

    def record(actor, decision)
      return if decision.allowed?

      # The detective half of the preventive control (M01-05 AC4). A refusal that
      # only reaches the application log is a refusal nobody queries: the audit
      # trail is where "who was turned away from what, and why" has to live.
      #
      # `resource` is not available here — only the decision — so the record
      # carries the type and id the decision already resolved.
      record_denial(actor, decision)

      Rails.logger.info(
        event: "authorization.denied",
        actor_id: actor.respond_to?(:external_id) ? actor.external_id : nil,
        action: decision.action,
        resource_type: decision.resource_type,
        resource_id: decision.resource_id,
        team_id: decision.team_id,
        reason: decision.reason
      )
    end

    # Written outside any transaction the caller may hold: a denial performs no
    # mutation, so there is nothing for a failed insert to roll back, and losing
    # the request because the trail could not be written would turn an audit
    # problem into an outage.
    def record_denial(actor, decision)
      AuditLog.create!(
        team_id: team_id_of(decision),
        actor_type: actor.is_a?(User) ? "USER" : "SYSTEM",
        actor_id: actor.is_a?(User) ? actor.id : nil,
        action: AuditLog::ACTIONS[:authorization_denied],
        resource_type: decision.resource_type,
        resource_id: internal_id(decision.resource_type, decision.resource_id),
        request_id: Current.request_id.presence || Current.correlation_id,
        correlation_id: Current.correlation_id,
        before: {},
        # Through the sanitiser like every other payload, even though the value is
        # a fixed vocabulary today. A second path into `after` that skips the
        # allowlist is a second path to maintain, and the guarantee "nothing
        # reaches an audit payload unsanitised" should be mechanical rather than
        # a promise about what this hash currently contains.
        after: AuditSanitizer.call(AuditSanitizer::DENIAL_TYPE, { "reason" => decision.reason.to_s }),
        result: "DENIED",
        created_at: Time.current
      )
    end

    def team_id_of(decision)
      return nil if decision.team_id.blank?

      Opanel::Identifier.parse(:team, decision.team_id)
    rescue Opanel::Identifier::InvalidIdentifier
      nil
    end

    def internal_id(resource_type, external)
      return nil if external.blank?

      type = resource_type.to_s.underscore.to_sym
      Opanel::Identifier.parse(type, external)
    rescue Opanel::Identifier::InvalidIdentifier, Opanel::Identifier::UnknownType
      nil
    end
  end
end
