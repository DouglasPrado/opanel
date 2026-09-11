# The Teams a user may act in, with the role they hold (doc 04 §18.1).
#
# A Query Object because the read is not a model's shape: it joins the membership
# to project the caller's own role and the date they joined, and it selects only
# the columns the page renders. Membership is the filter — a Team the user was
# suspended from disappears from this list on the very next request, which is
# what makes the suspension real without anything being invalidated.
class TeamsForUser
  # Pagination is mandatory for a collection that can grow (Annex I §7.3). A
  # person on more than a hundred Teams is implausible; loading an unbounded set
  # is not a read, it is a way for the page to fail for exactly one account.
  LIMIT = 100

  Entry = Data.define(:id, :name, :slug, :role, :status, :joined_at)

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    # Through the helper, so every domain Query in the product reads its tenancy
    # boundary from the same place (AC5). It resolves to `Team.accessible_to`.
    rows = TenantScope.for(user, Team).relation
      .order(:name, :id)
      .limit(LIMIT)
      .pluck(:id, :name, :slug, :status, "team_members.role", "team_members.joined_at")

    rows.map do |id, name, slug, status, role, joined_at|
      Entry.new(
        id: Opanel::Identifier.external(:team, id),
        name: name,
        slug: slug,
        role: role,
        status: status,
        joined_at: joined_at
      )
    end
  end

  private

  attr_reader :user
end
