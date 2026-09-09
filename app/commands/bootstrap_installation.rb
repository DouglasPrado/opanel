# The first registration completes the installation (doc 04 §3.1): it creates the
# initial Team, seats its creator as OWNER, and grants INSTANCE_ADMIN — and only
# that first registration does. Every later one is an ordinary sign-up.
#
# It is not a route. It runs **inside** `RegisterUser`'s transaction, because AC1
# says User, Team, membership and instance role are written in one transaction and
# AC8 says an interruption leaves nothing partial. Opening a second transaction
# here would produce exactly the partial state both criteria forbid.
#
# ## What decides, and what merely guards
#
# Two questions look the same and are not. "Did somebody else already bootstrap
# **at this instant**?" cannot be answered by a read: under two simultaneous first
# registrations both reads return nothing and both write, which is the race AC2
# exists to rule out, and re-reading does not help because neither transaction
# sees the other before COMMIT. That question is answered by
# `index_instance_roles_single_bootstrap` — a unique index over a constant
# expression, so at most one row in the table. The loser catches `RecordNotUnique`
# and reports that it did not bootstrap.
#
# "Did this installation already belong to somebody **before today**?" is a
# different question, and a read answers it perfectly well, because the answer
# cannot change underneath: users that already committed stay committed. That is
# `already_populated?`, and it exists because doc 04 §3.1 and AC1 say *empty
# installation*, not *installation without a bootstrap row*. Without it, deploying
# this migration onto a running installation would hand INSTANCE_ADMIN to the next
# person who used the open sign-up form.
#
# Do not remove the guard on the grounds that a read cannot decide a race. It is
# not deciding the race; the index still does.
#
# The Story's failure table asks for precisely this: "o segundo vira cadastro
# normal sem INSTANCE_ADMIN".
class BootstrapInstallation
  # Slug and name of the Team the first user gets. The Story does not ask the user
  # for one — the installation has to be usable immediately — and M11 is where
  # renaming a Team belongs.
  INITIAL_TEAM_NAME = "Default"
  INITIAL_TEAM_SLUG = "default"

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  # Returns a Result whose value says whether this registration was the bootstrap.
  # A registration that lost the race is a success, not a failure: the user exists
  # and is signed in, they simply administer nothing.
  def call
    # doc 04 §3.1 and AC1 both say *empty installation*, and "no bootstrap row
    # yet" is not the same predicate. They diverge exactly where it is dangerous:
    # an installation already running M01-02, with users and Teams, gets this
    # migration and an empty `instance_roles` — and the next self-service
    # registration, from whoever reaches the open sign-up form first, would become
    # the administrator of somebody else's installation, permanently, because the
    # singleton slot is then occupied and `GrantInstanceRole` requires an existing
    # admin.
    #
    # The guard is a read, and a read cannot decide a race — but it does not need
    # to. The race is still decided by the index below; this only refuses the case
    # where the installation demonstrably already belonged to somebody. Inside the
    # caller's transaction the user being registered is already visible, so the
    # question is whether anybody *else* exists.
    return Opanel::Result.success(bootstrapped: false) if already_populated?

    # A SAVEPOINT, not a second transaction. A unique violation aborts the
    # enclosing transaction in PostgreSQL — the caller's registration would die
    # with it, and rescuing afterwards would run against a transaction that can no
    # longer execute anything. Rolling back to a savepoint discards the losing
    # attempt and leaves the User and Session written by `RegisterUser` intact, so
    # the loser really does become an ordinary sign-up. The COMMIT is still one,
    # which is what AC1 asks for.
    ApplicationRecord.transaction(requires_new: true) do
      # The instance role is written **first**, and the order is load-bearing: it
      # is the row the singleton index guards, so the race is decided before this
      # transaction touches anything else. Writing the Team first would make two
      # simultaneous first registrations collide on the Team's slug instead —
      # the same outcome by accident, reported as the wrong error, and dependent
      # on a slug that a later Story could make unique per installation.
      role = InstanceRole.create!(user: user, role: InstanceRole::ADMIN,
        granted_by_bootstrap: true)
      team = Team.create!(name: INITIAL_TEAM_NAME, slug: available_slug,
        owner_user_id: user.id, status: "ACTIVE")
      membership = TeamMember.create!(team: team, user: user, role: "OWNER",
        status: "ACTIVE", joined_at: Time.current)

      return Opanel::Result.success(bootstrapped: true, team: team, membership: membership,
        instance_role: role)
    end
  rescue ActiveRecord::RecordNotUnique => error
    # Only the singleton index means "somebody else bootstrapped". Any other
    # unique violation is a real defect and must not be swallowed into a quiet
    # "this was not the first registration".
    raise unless error.message.include?("index_instance_roles_single_bootstrap")

    Opanel::Result.success(bootstrapped: false)
  end

  private

  attr_reader :user

  # Whether this installation already belonged to somebody before this
  # registration. The user being registered is already written in the caller's
  # transaction, so "anybody else" is the question — and a concurrent first
  # registration is invisible here, which is correct: it has not committed, and
  # the index below is what decides between the two.
  def already_populated?
    User.where.not(id: user.id).exists?
  end

  # Always distinct, never a lookup. `Team.where(slug:).exists?` was a
  # time-of-check/time-of-use read: two registrations could both find `default`
  # free and collide on `index_teams_unique_slug_when_not_deleted`, which
  # `RegisterUser` reports as EMAIL_UNAVAILABLE — losing a registration and
  # blaming the address for it. Suffixing unconditionally removes the check, and
  # therefore the window.
  def available_slug
    "#{INITIAL_TEAM_SLUG}-#{Opanel::Identifier.generate.downcase.last(8)}"
  end
end
