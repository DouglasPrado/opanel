# Suspends a membership: access to the Team stops, the history stays (doc 04
# §5.2, AC8).
#
# Suspension is not a session action. Nothing about Team access lives in the
# cookie or in the session row, so there is nothing to invalidate — the next
# request re-reads the membership and finds it no longer ACTIVE (Annex C §7.2).
#
# **Who may suspend whom.** Since M01-04 the role question belongs to
# `TeamPolicy#manage_members?` (doc 04 §6.2). What stays here are the invariants
# about the *target*, from doc 04 §3.2, which no role widens:
#
#   * the actor must be permitted to manage members of this Team, which the
#     Policy decides;
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

    # Two questions, asked in this order. "May this actor manage members here?" is
    # the Policy's, and it must be answered first: somebody outside the Team may
    # not learn anything about the target, not even that suspending the OWNER is
    # forbidden.
    refusal = refusal_for(target) || target_refusal_for(target)
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

    # The decision belongs to `TeamPolicy#manage_members?` (doc 04 §6.2), not to a
    # role list written here. Before M01-04 this Command carried its own copy of
    # "OWNER or ADMIN"; a rule duplicated per Command is a rule that drifts, and
    # the point of the Policy layer is that there is one place to read and to
    # change it.
    #
    # The Policy is named and its predicate called, rather than reached through a
    # generic helper, and that is deliberate: `grep manage_members?` is how the
    # next person finds where this permission is decided, and AF-07 reads the
    # Command for exactly this to prove the mutation has an authorization path.
    policy = TeamPolicy.new(actor, team)
    return nil if policy.manage_members?

    # Only on the denied path, and only then, is the reason worth a second
    # evaluation: it is what separates "you are not on this Team" from "you are,
    # but not with that role".
    decision = policy.decide(:manage_members)
    Opanel::Authorization.record(actor, decision)

    # A denial for want of a membership is answered as NOT_FOUND, the same as a
    # member who is not on the Team: an actor outside the Team must not learn
    # that it exists (Annex C §7.3, AC4).
    return failure("NOT_FOUND", NOT_FOUND_MESSAGE) if decision.reason == :no_membership

    failure("FORBIDDEN", FORBIDDEN_MESSAGE)
  end

  def target_refusal_for(target)
    # The security procedure is exempt from these, and only from these: suspending
    # the OWNER is precisely what it exists to do (doc 04 §3.2), and it has no
    # user to be "itself".
    return nil if security_procedure?

    # Rules about *this* target rather than about the actor's role, so they stay
    # here: the Policy answers "may this actor manage members", and these answer
    # "is this particular change allowed at all".
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
