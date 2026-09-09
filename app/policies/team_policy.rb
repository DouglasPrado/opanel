# The matrix of doc 04 §6.2, for a Team and the resources scoped to it.
#
# Every action of that table is declared, including the ones whose Command does
# not exist yet. That is deliberate and it is not speculative abstraction: the
# matrix is a **decision already taken** in approved documentation, and writing it
# down once means the Story that brings `DeployRelease` adds a Command against a
# rule that was already agreed and tested, rather than inventing the rule while
# implementing the feature. The rules are data; the code that reads them is the
# same three lines for all of them.
#
# `permitted_roles` raises for anything not listed, so this table is also the
# complete inventory of what the product knows how to authorize.
class TeamPolicy < ApplicationPolicy
  OWNER = "OWNER"
  ADMIN = "ADMIN"
  DEVELOPER = "DEVELOPER"
  VIEWER = "VIEWER"

  ALL_ROLES = [ OWNER, ADMIN, DEVELOPER, VIEWER ].freeze
  MANAGERS = [ OWNER, ADMIN ].freeze
  CONTRIBUTORS = [ OWNER, ADMIN, DEVELOPER ].freeze

  # doc 04 §6.2, row by row. The asterisks in that table mean "dependent on the
  # Team's scope/policy", which is M11-08; until then a role either permits the
  # action or it does not.
  PERMISSIONS = {
    # Reserved to the OWNER, and the reason is in doc 04 §3.2: ADMIN may never
    # create an OWNER, so neither of these can widen.
    transfer_ownership: [ OWNER ].freeze,
    delete_team: [ OWNER ].freeze,
    rotate_recovery_key: [ OWNER ].freeze,

    manage_members: MANAGERS,
    manage_clusters: MANAGERS,
    drain_node: MANAGERS,
    reveal_production_secret: MANAGERS,

    create_project: CONTRIBUTORS,
    create_environment: CONTRIBUTORS,
    deploy: CONTRIBUTORS,
    rollback: CONTRIBUTORS,
    restart_service: CONTRIBUTORS,
    scale_service: CONTRIBUTORS,
    edit_secret: CONTRIBUTORS,

    # Everyone with an active membership, VIEWER included — the read that makes a
    # Team usable at all.
    view: ALL_ROLES,
    view_logs: ALL_ROLES,
    view_metrics: ALL_ROLES
  }.freeze

  def self.permissions = PERMISSIONS

  # One predicate per action, written out rather than generated.
  #
  # `define_method` in a loop would be shorter and worse for two reasons. AF-07
  # greps the Policy file for `def <action>?`, so generated predicates leave the
  # fitness function unable to see that the rule exists — the check would pass
  # only because it found nothing to check. And `grep manage_members?` is how
  # somebody finds out where a permission is decided; metaprogramming costs them
  # that, to save seventeen lines.
  def transfer_ownership? = decide(:transfer_ownership).allowed?
  def delete_team? = decide(:delete_team).allowed?
  def rotate_recovery_key? = decide(:rotate_recovery_key).allowed?
  def manage_members? = decide(:manage_members).allowed?
  def manage_clusters? = decide(:manage_clusters).allowed?
  def drain_node? = decide(:drain_node).allowed?
  def reveal_production_secret? = decide(:reveal_production_secret).allowed?
  def create_project? = decide(:create_project).allowed?
  def create_environment? = decide(:create_environment).allowed?
  def deploy? = decide(:deploy).allowed?
  def rollback? = decide(:rollback).allowed?
  def restart_service? = decide(:restart_service).allowed?
  def scale_service? = decide(:scale_service).allowed?
  def edit_secret? = decide(:edit_secret).allowed?
  def view? = decide(:view).allowed?
  def view_logs? = decide(:view_logs).allowed?
  def view_metrics? = decide(:view_metrics).allowed?

  private

  # A `TeamPolicy` is constructed either with a Team or with something that
  # belongs to one. Resolving it here, rather than at each call site, is what
  # keeps "the scope is explicitly loaded" from depending on the caller
  # remembering.
  def team
    return resource if resource.is_a?(Team)
    return resource.team if resource.respond_to?(:team)

    nil
  end
end
