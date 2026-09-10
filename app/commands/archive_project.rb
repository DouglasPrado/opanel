# Archives a Project: `ACTIVE → ARCHIVED` (doc 09 §5.1, AC8).
#
# Archiving is not deletion. The row stays, the slug stays reserved among the
# Team's living Projects, and nothing about the runtime changes — doc 09 §25 puts
# removal behind `DELETING → reconcile → tombstone`, which is `M02-09`. In M01 a
# Project is taken out of the way, and that is all.
#
# ## AC5 — the guard that cannot be written yet
#
# The Story asks for archiving to be **blocked when the Project has active
# Environments**. `Environment` does not exist: it is created by `M01-11`, whose
# own precondition is this Story being done. The dependency is circular and it is
# written in both Story files; it is recorded as `SC-18` in
# `docs/implementation/SPEC_CONFLICTS.md`, and `M01-11` inherits the obligation to
# close it.
#
# What is *not* done here is worth naming, because it would look like diligence:
# no `environments` table is created (out of scope, and it would collide with
# `M01-11`'s boundary), and no registry of "archival blockers" with a single
# empty implementation is introduced — an abstraction with no second caller is
# the speculative kind `AGENT_RULES` forbids. The guard's place is marked and the
# criterion is reported as deferred rather than claimed.
#
# Today the rule is vacuously true: with no Environments in the system, no Project
# can have an active one. Vacuously true is not proven, and this Command does not
# pretend otherwise.
class ArchiveProject
  ALREADY_ARCHIVED = "This project is already archived."
  BEING_DELETED = "This project is being deleted and can no longer be archived."

  def self.call(actor:, project:)
    new(actor: actor, project: project).call
  end

  def initialize(actor:, project:)
    @actor = actor
    @project = project
  end

  def call
    Opanel::Authorization.authorize!(actor, :archive, project)

    guard = blocking_reason
    return failure("CONFLICT", guard, field: "status") if guard

    # TODO(M01-11): refuse when the Project has an active Environment, and prove
    # it with the case planted — this is AC5, deferred by SC-18.

    persist
  end

  private

  attr_reader :actor, :project

  # Why this Project may not be archived, or `nil`. Read from the state machine
  # rather than from a chain of conditionals, so "what may follow ACTIVE" is
  # written in exactly one place.
  def blocking_reason
    return nil if project.can_transition_to?(Project::ARCHIVED)

    project.deleting? ? BEING_DELETED : ALREADY_ARCHIVED
  end

  def persist
    before = { "status" => project.status }

    ApplicationRecord.transaction do
      project.update!(status: Project::ARCHIVED)

      AuditTrail.record(action: :project_archived, actor: actor, resource: project,
        before: before, after: { "status" => project.status })
    end

    Rails.logger.info(event: "project.archived", team_id: project.team.external_id,
      project_id: project.external_id, actor_id: actor.external_id, result: "succeeded")

    Opanel::Result.success(project: project)
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "project.archived", team_id: project.team&.external_id,
      project_id: project.external_id, actor_id: actor&.external_id,
      result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
