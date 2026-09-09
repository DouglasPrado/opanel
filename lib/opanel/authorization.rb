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
      "TeamMember" => "TeamPolicy"
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
  end
end
