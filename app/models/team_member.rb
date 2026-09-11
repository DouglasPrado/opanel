# Somebody's membership of a Team, with the role and the lifecycle of doc 04 §5.
#
# The row outlives the access: REMOVED is a status, never a `DELETE`, because the
# audit trail of who had access to a Team is part of what the Team is (doc 04
# §5.2). `UNIQUE(team_id, user_id)` therefore also means a removed member keeps
# their row forever — re-admitting somebody reuses it rather than adding a second.
class TeamMember < ApplicationRecord
  include UlidPrimaryKey

  # doc 04 §5.1 also lists BILLING as optional for a later phase; it is outside
  # this Story's scope and adding it is an expand migration on the CHECK.
  ROLES = %w[OWNER ADMIN DEVELOPER VIEWER].freeze
  STATUSES = %w[INVITED ACTIVE SUSPENDED REMOVED].freeze

  # The one status that grants access to the Team. Named rather than inlined
  # because both the scope and `Team.accessible_to` depend on it being the same
  # answer in both places.
  ACCESS_GRANTING_STATUS = "ACTIVE"

  # The statuses in which an OWNER still holds the seat: ACTIVE, or SUSPENDED
  # while the Team waits for the recovery of M11-04. A REMOVED OWNER has left and
  # keeps only the audit trail (AC9). Mirrors the predicate of
  # `index_team_members_one_active_owner_per_team`.
  LIVING_OWNER_STATUSES = %w[ACTIVE SUSPENDED].freeze

  # doc 04 §5.2, written out. REMOVED is terminal: a membership that ended is
  # history, and restoring access is a new decision somebody has to make
  # explicitly rather than a status flipped back.
  TRANSITIONS = {
    "INVITED" => %w[ACTIVE REMOVED],
    "ACTIVE" => %w[SUSPENDED REMOVED],
    "SUSPENDED" => %w[ACTIVE REMOVED],
    "REMOVED" => []
  }.freeze

  belongs_to :team
  belongs_to :user
  belongs_to :inviter, class_name: "User", foreign_key: :invited_by, optional: true, inverse_of: false

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :joined_at, presence: true, unless: -> { status == "INVITED" }

  validate :status_transition_is_allowed, on: :update
  validate :ownership_is_not_claimed
  validate :ownership_is_not_abandoned, on: :update

  scope :active, -> { where(status: ACCESS_GRANTING_STATUS) }
  scope :owners, -> { where(role: "OWNER") }

  def owner?
    role == "OWNER"
  end

  def grants_access?
    status == ACCESS_GRANTING_STATUS
  end

  private

  def status_transition_is_allowed
    return unless status_changed?
    return if TRANSITIONS.fetch(status_was, []).include?(status)

    errors.add(:status, "cannot move from #{status_was} to #{status}")
  end

  # The server-side half of "there is no path to OWNER except the explicit
  # transfer" (doc 04 §3.2). The database half is
  # `index_team_members_one_active_owner_per_team`, which makes a second living
  # OWNER impossible whatever the caller intended.
  #
  # It runs on create as well as on update, and the distinction matters: guarding
  # only `update` left ownership claimable by a row *born* OWNER. A caller that
  # passes `role:` straight from a request — which is exactly what M11-01's
  # invitation will do — could seat a second OWNER on a Team in
  # OWNERSHIP_RECOVERY_REQUIRED, where the suspended ex-OWNER satisfies the
  # foreign key and the ACTIVE slot used to be free. The claim has to be refused
  # wherever it is made, not only where it is edited.
  #
  # The one legitimate birth is the first: `CreateTeam` seats the creator as
  # OWNER of a Team that has no other membership. That case is recognised by the
  # absence of any other living OWNER, so it needs no flag to skip the rule and
  # no `save(validate: false)` to get around it.
  #
  # M11-03 owns the transfer. When it arrives it will demote the current OWNER
  # and promote the new one in one transaction, and it will have to go through an
  # explicit path here rather than around this validation — that is the point of
  # the validation existing before the feature does.
  def ownership_is_not_claimed
    return unless role == "OWNER"
    return if persisted? && !role_changed?
    # A REMOVED OWNER claims nothing — it is the audit trail AC9 requires to
    # survive, and the only birth that is not a claim. INVITED is deliberately
    # *not* exempt: an invitation to be OWNER is a claim that has not landed yet,
    # and letting it be written would move the refusal to the moment it is
    # accepted, where it arrives as a raw unique-violation instead of a message
    # the inviter can act on.
    return if new_record? && status == "REMOVED"
    return if new_record? && !other_living_owner?

    errors.add(:role, "cannot be claimed: ownership changes only through an explicit transfer")
  end

  # A living OWNER is one who still holds the seat: ACTIVE, or SUSPENDED while
  # the Team waits for recovery. A REMOVED one has left and keeps only the audit
  # trail (AC9). Mirrors the predicate of
  # `index_team_members_one_active_owner_per_team`, so the domain refuses what
  # the database would refuse — with a message a user can act on.
  def other_living_owner?
    return false if team_id.blank?

    scope = TeamMember.owners.where(team_id: team_id, status: LIVING_OWNER_STATUSES)
    scope = scope.where.not(id: id) if id.present?
    scope.exists?
  end

  # The other half of AC5: the OWNER cannot walk away either — not by changing
  # role, not by suspending or removing themselves. "OWNER tenta se remover →
  # rejeitado com erro estável explicando que é preciso transferir ownership
  # primeiro" (the Story's Failure Scenarios).
  #
  # The expected pairing is read from the Team **in this transaction**, and it is
  # deliberately the same expression as the `owner_membership_status` generated
  # column: an ACTIVE Team expects its OWNER ACTIVE, a Team in
  # OWNERSHIP_RECOVERY_REQUIRED expects them SUSPENDED. The domain therefore
  # refuses exactly what `fk_teams_active_owner_membership` would refuse at
  # COMMIT — with a message a user can act on instead of a raised PG error. The
  # database remains the enforcement; this is the explanation.
  def ownership_is_not_abandoned
    return unless role_was == "OWNER"
    return unless role_changed? || status_changed?

    expected_status = Team.where(id: team_id, owner_user_id: user_id).pick(
      Arel.sql("CASE WHEN status = 'OWNERSHIP_RECOVERY_REQUIRED' THEN 'SUSPENDED' ELSE 'ACTIVE' END")
    )

    # Not the membership the Team points at — an OWNER row of some earlier
    # ownership, which is free to change.
    return if expected_status.nil?
    return if role == "OWNER" && status == expected_status

    errors.add(:base, "The owner cannot leave the team. Transfer ownership first.")
  end
end
