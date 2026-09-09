# Suspends a membership: access to the Team stops, the history stays (doc 04
# §5.2, AC8).
#
# Suspension is not a session action. Nothing about Team access lives in the
# cookie or in the session row, so there is nothing to invalidate — the next
# request re-reads the membership and finds it no longer ACTIVE (Annex C §7.2).
#
# **Who may suspend whom.** Policies arrive in M01-04; the rules here are the
# domain invariants of doc 04 §3.2, and they are deliberately narrow:
#
#   * the actor must hold an ACTIVE OWNER or ADMIN membership of the same Team;
#   * nobody suspends themselves — for the OWNER that would leave the Team
#     without one, and for anybody else it is a mistake, not a feature;
#   * **no Team member, of any role, may suspend the OWNER.** An ADMIN who could
#     suspend the OWNER would have found a path to ownership that is not the
#     explicit transfer of M11-03.
#
# Suspending the OWNER is a security procedure, not a Team operation, and doc 04
# §3.2 pairs it with the Team entering OWNERSHIP_RECOVERY_REQUIRED. That path is
# `SECURITY_PROCEDURE`: it is reachable from no route in this Story, INSTANCE_ADMIN
# is M01-03 and the recovery itself is M11-04.
class SuspendTeamMember
  # The non-user actor of the security procedure. A constant rather than `nil`,
  # so a bug that forgets to pass an actor cannot silently become the privileged
  # path.
  SECURITY_PROCEDURE = :security_procedure

  NOT_FOUND_MESSAGE = "That member is not on this team."
  INVALID_MESSAGE = "That is not a valid user identifier."
  SELF_MESSAGE = "You cannot suspend your own membership."
  OWNER_MESSAGE = "The owner cannot be suspended from inside the team. Transfer ownership first."
  FORBIDDEN_MESSAGE = "You cannot change members of this team."

  def self.call(actor:, team:, user_id:)
    new(actor: actor, team: team, user_id: user_id).call
  end

  def initialize(actor:, team:, user_id:)
    @actor = actor
    @team = team
    @user_id = user_id
  end

  def call
    id = Opanel::Identifier.parse(:user, user_id)
    target = team.team_members.find_by(user_id: id)

    return failure("NOT_FOUND", NOT_FOUND_MESSAGE) if target.nil?

    refusal = refusal_for(target)
    return refusal if refusal

    # Idempotent: suspending an already suspended membership is the state the
    # caller asked for, so a retry and a double-clicked button agree.
    return Opanel::Result.success(target) if target.status == "SUSPENDED"

    suspend(target)
  rescue Opanel::Identifier::InvalidIdentifier => error
    # ADR-0002 §4: the wrong kind of identifier is a validation failure, never a
    # NOT_FOUND — answering NOT_FOUND would turn type confusion into an
    # existence oracle.
    failure(error.code, INVALID_MESSAGE)
  end

  private

  attr_reader :actor, :team, :user_id

  def security_procedure?
    actor == SECURITY_PROCEDURE
  end

  def refusal_for(target)
    return nil if security_procedure?

    # Scoped to an ACTIVE membership of *this* Team: an actor who is not on the
    # Team is answered exactly as one asking about a member who is not on it.
    actor_membership = team.team_members.active.find_by(user_id: actor.id)

    return failure("NOT_FOUND", NOT_FOUND_MESSAGE) if actor_membership.nil?
    return failure("FORBIDDEN", FORBIDDEN_MESSAGE) unless %w[OWNER ADMIN].include?(actor_membership.role)
    return failure("FORBIDDEN", SELF_MESSAGE) if target.user_id == actor.id
    return failure("FORBIDDEN", OWNER_MESSAGE) if target.owner?

    nil
  end

  def suspend(target)
    ApplicationRecord.transaction do
      # The Team row is locked before either write. Suspending the OWNER is a
      # read-modify-write across two rows, and the lock is what makes two
      # simultaneous administrative actions on one Team serialize rather than
      # interleave. The database still has the last word: the composite key is
      # verified at COMMIT.
      team.lock!

      # The Team moves **first** when the OWNER is the target, and the order is
      # load-bearing rather than stylistic: `TeamMember` refuses to let the OWNER
      # leave the pairing the Team expects, so the Team has to declare that it is
      # in recovery before the membership is allowed to become SUSPENDED. Both
      # writes are in one transaction and the composite key judges the pair at
      # COMMIT, so no order can produce a state that survives being wrong.
      if target.owner?
        team.update!(status: "OWNERSHIP_RECOVERY_REQUIRED")

        Rails.logger.warn(event: "team.ownership.recovery_required", team_id: team.external_id,
          actor_id: actor_id_for_log, result: "succeeded")
      end

      target.update!(status: "SUSPENDED")
    end

    Rails.logger.info(event: "team.member.suspended", team_id: team.external_id,
      member_id: target.external_id, actor_id: actor_id_for_log, result: "succeeded")

    Opanel::Result.success(target)
  end

  def actor_id_for_log
    security_procedure? ? SECURITY_PROCEDURE.to_s : actor.external_id
  end

  def failure(code, message)
    Rails.logger.info(event: "team.member.suspended", team_id: team.external_id,
      actor_id: actor_id_for_log, result: "rejected", reason: code)

    Opanel::Result.failure(code: code, message: message)
  end
end
