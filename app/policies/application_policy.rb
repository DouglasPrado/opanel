# The authorization decision, in the shape doc 04 §6 draws it:
#
#   authorize(actor, action, resource)
#     -> membership active?
#     -> role permits action?
#     -> scope includes resource?
#     -> environment restrictions?
#     -> policy / guardrail permits?
#
# A Policy **decides**; it never acts (Annex I §4.1). The Command performs the
# mutation after the decision, and the same Policy is what the UI, the public API,
# the CLI and MCP go through — authorization is not duplicated per delivery
# channel.
#
# ## Deny by default is a mechanism here, not a convention
#
# `PERMISSIONS` maps action -> the roles that may perform it. An action that is
# not in the map is not "unrestricted": `permitted_roles` raises
# `UnregisteredAction`, so forgetting to register an action fails loudly the first
# time it is exercised instead of silently allowing everybody. AC2 asks for
# exactly that — the omission is a programming error a test detects, not an
# implicit permission.
#
# ## Why the matrix lives in the Policy and not in the database
#
# doc 04 §6.2 is a decision about the product, not configuration a user edits;
# per-Environment permissions that a Team configures are M11-08. Keeping it in
# code means a change to who may do what arrives as a reviewable diff with tests,
# which is what "server-enforced invariants" means in AGENT_RULES.
class ApplicationPolicy
  class UnregisteredAction < StandardError; end

  # doc 04 §6.1. VAULT is declared and unused until M03 — the Story asks for the
  # scope to exist so the shape of a decision does not change when secrets arrive.
  SCOPES = %i[team cluster project environment service vault].freeze

  # Why a denial happened, classified. The Story's Observability Requirements ask
  # for the reason, and "denied" alone cannot tell an operator whether somebody
  # lost their membership or simply lacks the role.
  REASONS = {
    no_membership: "the actor has no active membership of this team",
    insufficient_role: "the actor's role does not permit this action",
    out_of_scope: "the resource is outside the actor's scope",
    unregistered_action: "no rule is registered for this action, so it is denied"
  }.freeze

  Decision = Struct.new(:allowed, :reason, :action, :resource_type, :resource_id,
    :team_id, keyword_init: true) do
    def allowed? = allowed
    def denied? = !allowed
  end

  def initialize(actor, resource)
    @actor = actor
    @resource = resource
  end

  attr_reader :actor, :resource

  # Subclasses declare their matrix. Empty here on purpose: a Policy that forgot
  # to declare anything denies everything.
  def self.permissions = {}

  # The roles allowed to perform `action`, or a raise when the action was never
  # registered. Raising rather than returning `[]` is what makes AC2's "detected
  # as a programming error" possible: an empty list is indistinguishable from a
  # deliberate "nobody may do this".
  def self.permitted_roles(action)
    permissions.fetch(action.to_sym) do
      raise UnregisteredAction,
        "#{name} has no rule for #{action.inspect}. Register it in `permissions` — " \
        "an unregistered action is denied, and silently denying a real action is a defect."
    end
  end

  def self.registered_actions = permissions.keys

  # The decision. Never raises for an ordinary denial: a refusal is data the
  # caller renders, and only an unregistered action is exceptional.
  def decide(action)
    return deny(:unregistered_action, action) unless registered?(action)

    membership = active_membership
    return deny(:no_membership, action) if membership.nil?
    return deny(:insufficient_role, action) unless role_permits?(action, membership.role)
    return deny(:out_of_scope, action) unless within_scope?(membership)

    allow(action)
  end

  private

  def registered?(action)
    self.class.registered_actions.include?(action.to_sym)
  end

  def role_permits?(action, role)
    self.class.permitted_roles(action).include?(role)
  end

  # The membership through which the actor reaches this resource, loaded
  # explicitly — never inferred from the route. Subclasses say how to get from the
  # resource to its Team.
  def active_membership
    return nil if actor.nil? || team.nil?

    TeamMember.active.find_by(team_id: team.id, user_id: actor.id)
  end

  # The Team the resource belongs to. Every tenant-scoped resource has an
  # unambiguous path to one (doc 09 §30, "Ownership").
  def team = raise(NotImplementedError, "#{self.class.name} must say which Team owns the resource")

  # Environment-level restrictions. The path exists here so a decision's shape
  # does not change when M11-08 makes them configurable; today nothing narrows a
  # membership beyond its role.
  def within_scope?(_membership) = true

  def allow(action)
    decision(true, nil, action)
  end

  def deny(reason, action)
    decision(false, reason, action)
  end

  def decision(allowed, reason, action)
    Decision.new(
      allowed: allowed, reason: reason, action: action.to_sym,
      resource_type: resource.class.name,
      resource_id: resource.respond_to?(:external_id) ? resource.external_id : nil,
      team_id: team&.external_id
    )
  end
end
