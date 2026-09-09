# The tenancy boundary, in the query.
#
# Annex C §7.3 is blunt: *"Nunca buscar recurso apenas por ID e depois 'confiar'
# que a rota está no Team correto"*. This is the helper that makes obeying it
# shorter than disobeying it, which is the only way a rule like that survives
# contact with a deadline.
#
#   TenantScope.for(User, Team).find(id)         # scoped, cannot leak
#   Team.find(id)                                # unscoped — the thing we forbid
#
# ## Why `nil` and not an exception for a miss
#
# A resource in another Team must be indistinguishable from one that does not
# exist (AC4). Returning `nil` for both, and letting the controller turn that into
# a single 404, is what makes the two cases identical **by construction** rather
# than by every caller remembering to rescue the same way. There is no code path
# here that can answer "it exists but is not yours".
#
# ## What this does not do
#
# It scopes; it does not authorize. A VIEWER and an OWNER of the same Team both
# pass this helper — what they may *do* with the resource is the Policy's answer.
# Scoping without a Policy leaks capability inside a Team; a Policy without
# scoping leaks data across Teams. Both are required, and they answer different
# questions.
class TenantScope
  class UnscopedRelation < StandardError; end

  def self.for(actor, model)
    new(actor, model)
  end

  def initialize(actor, model)
    @actor = actor
    @model = model
  end

  # Every row of `model` the actor may see, through an **active** membership.
  # Suspension therefore takes effect on the next query, with nothing to
  # invalidate — which is AC7, and the same property M01-02 relies on.
  def relation
    return @model.none if actor.nil?

    case @model.name
    when "Team"
      # Delegates to the scope M01-02 already wrote rather than restating it:
      # `accessible_to` also excludes soft-deleted Teams, and two definitions of
      # "which Teams may this user see" would eventually disagree.
      @model.accessible_to(actor)
    when "TeamMember"
      @model.where(team_id: active_team_ids)
    else
      raise UnscopedRelation,
        "#{@model.name} has no tenancy boundary registered in TenantScope. " \
        "Add one — a model without a boundary is a model that leaks across Teams."
    end
  end

  # `nil` when the row is absent *or* outside the boundary. The caller cannot tell
  # the two apart, and neither can the user.
  def find_by_external_id(type, external)
    id = Opanel::Identifier.parse(type, external)

    relation.find_by(id: id)
  end

  def find(id)
    relation.find_by(id: id)
  end

  private

  attr_reader :actor

  def active_team_ids
    TeamMember.active.where(user_id: actor.id).select(:team_id)
  end
end
