# Authorization for a Project that exists, against the matrix of doc 04 §6.2.
#
# ## Why this exists next to `TeamPolicy`
#
# `TeamPolicy` answers about the tenant. This one answers about a resource
# **inside** it, and the difference is not cosmetic: `ApplicationPolicy#decide`
# resolves the actor's membership from the resource's Team, so a Policy
# constructed with a Project scopes the decision to *that Project's* Team rather
# than to whichever Team the route happened to name. That is the difference
# between "an ADMIN may archive Projects" and "an ADMIN of this Team may archive
# this Project", and only the second is worth enforcing.
#
# ## Why creation is not here
#
# There is no Project yet when somebody asks to create one, so the resource of
# that decision is the Team — and `TeamPolicy` already declares the row of
# doc 04 §6.2 that governs it (`create_project`, tested by the role matrix of
# `M01-04`). `CreateProject` calls it directly.
#
# Declaring a second `create` here would put two answers to one question in the
# repository, and the wrong one would be whichever nobody remembered to update.
# The Story names `ProjectPolicy` as the place project permissions live; this is
# that place, minus the one decision that structurally cannot take a Project as
# its subject.
#
# ## Why the rules are references and not copies
#
# `view` and `update` are rows the matrix already assigns; they are read from
# `TeamPolicy::PERMISSIONS` rather than restated. A copy would be correct today
# and stale the first time the matrix changes — the Reuse Gate applied to a rule
# instead of to a component.
class ProjectPolicy < ApplicationPolicy
  PERMISSIONS = {
    # doc 04 §6.2, row "Ver logs e métricas" — VIEWER included. AC9: a VIEWER
    # reads and does not mutate, and this is the half that lets them read.
    view: TeamPolicy::PERMISSIONS.fetch(:view),

    # Renaming a Project changes a name in a URL and nothing about who may reach
    # it, so it carries the same roles the matrix gives creation. It deliberately
    # does not widen to VIEWER, which AC9 forbids.
    update: TeamPolicy::PERMISSIONS.fetch(:create_project),

    # The Story is explicit: *"arquivar exige ADMIN"*. Archiving takes a Project
    # out of everybody's list, so it sits with the management row of the matrix
    # (OWNER and ADMIN), not with the contributor row that governs creating one.
    archive: TeamPolicy::MANAGERS
  }.freeze

  def self.permissions = PERMISSIONS

  # Written out rather than generated, for the reason `TeamPolicy` records: AF-07
  # greps for `def <action>?`, and a generated predicate leaves the fitness
  # function passing because it found nothing to check.
  def view? = decide(:view).allowed?
  def update? = decide(:update).allowed?
  def archive? = decide(:archive).allowed?

  private

  def team = resource.is_a?(Project) ? resource.team : nil
end
