# The tenant of the product (doc 09 §3.2, doc 04 §2).
#
# `owner_user_id` is not the authorization answer — the membership is. It exists
# so that ownership is a column the database can constrain, and it is kept in
# agreement with the OWNER + ACTIVE membership by `fk_teams_active_owner_membership`
# rather than by any code here. `owner_role` and `owner_membership_status` are
# generated columns that exist only so that key can be declarative; nothing reads
# them and nothing can write them.
class Team < ApplicationRecord
  include UlidPrimaryKey

  # ACTIVE is the ordinary state. OWNERSHIP_RECOVERY_REQUIRED is what a Team
  # enters when its OWNER is suspended by a security procedure (doc 04 §3.2);
  # leaving it is M11-04's administrative recovery, which this Story does not
  # implement.
  STATUSES = %w[ACTIVE OWNERSHIP_RECOVERY_REQUIRED].freeze

  NAME_MAX_LENGTH = 120
  SLUG_MIN_LENGTH = 2
  SLUG_MAX_LENGTH = 63
  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  belongs_to :owner, class_name: "User", foreign_key: :owner_user_id, inverse_of: false

  # `restrict_with_error` rather than `destroy`: a membership is the record of
  # who had access, and doc 04 §5.2 keeps it after REMOVED. Deleting a Team is
  # not this Story's scope and must not become possible by accident.
  has_many :team_members, dependent: :restrict_with_error
  has_many :members, through: :team_members, source: :user

  # `restrict_with_error` for the reason above and one more: doc 09 §25 makes a
  # Project's removal a lifecycle (`DELETING` → reconcile → tombstone), not a
  # cascade. A Team that deleted its Projects on the way out would destroy
  # desired state the runtime is still converging toward.
  has_many :projects, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :slug, presence: true, format: { with: SLUG_FORMAT },
    length: { in: SLUG_MIN_LENGTH..SLUG_MAX_LENGTH }
  validates :status, inclusion: { in: STATUSES }

  scope :kept, -> { where(deleted_at: nil) }

  # The only way a request should reach a Team. Scoped in the query rather than
  # fetched by id and checked afterwards (Annex C §7.3), and joined on the
  # membership so a suspension takes effect on the very next request — there is
  # nothing to invalidate because there is nothing cached.
  scope :accessible_to, ->(user) {
    kept.joins(:team_members)
      .where(team_members: { user_id: user.id, status: TeamMember::ACCESS_GRANTING_STATUS })
  }

  # A URL-safe name derived from what the user typed. Deterministic and total:
  # anything that cannot produce a valid slug produces nil, so the caller has to
  # decide what to do rather than persisting something the CHECK will reject.
  def self.slugify(value)
    candidate = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
    candidate = candidate.first(SLUG_MAX_LENGTH).delete_suffix("-")

    candidate.match?(SLUG_FORMAT) && candidate.length >= SLUG_MIN_LENGTH ? candidate : nil
  end

  def active?
    status == "ACTIVE"
  end

  def ownership_recovery_required?
    status == "OWNERSHIP_RECOVERY_REQUIRED"
  end

  # The membership the foreign key points at. Looked up by role as well as by
  # user, so a Team in recovery still answers with the suspended OWNER rather
  # than with whoever else happens to be on it.
  def owner_membership
    team_members.find_by(user_id: owner_user_id, role: "OWNER")
  end
end
