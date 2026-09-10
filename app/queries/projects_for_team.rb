# The Projects of a Team, one page at a time (AC6, doc 09 §23).
#
# ## Why keyset and not `OFFSET`
#
# AC6 asks for a listing that *"permanece estável sob inserções concorrentes"*,
# and `LIMIT/OFFSET` cannot be: a row inserted before the reader's position
# shifts every later page by one, so an item is silently skipped and another is
# shown twice. The cursor here is the last id of the page, and the next page is
# everything greater than it. Because the id is a ULID — monotonic within a
# millisecond by construction (ADR-0002) — a concurrent insert always lands
# *after* the reader, and a page already served cannot change.
#
# The index `index_projects_on_team_id_and_id` is what makes this a range scan
# rather than a sort of the Team's whole set.
#
# ## The cursor is external, and it is validated
#
# It travels as `prj_01HX…` because it appears in a URL, and it is parsed through
# `Opanel::Identifier` — a value carrying another type's prefix is a validation
# failure, never a NOT_FOUND (ADR-0002 §4). A malformed cursor must not be able to
# ask this query anything.
class ProjectsForTeam
  # A page size a screen can render and a database can plan. Pagination is
  # mandatory for a collection that grows (Annex I §7.3); an unbounded read is not
  # a read, it is a way for the page to fail for exactly one Team.
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  Entry = Data.define(:id, :name, :slug, :description, :status, :created_at)

  # `next_cursor` is `nil` on the last page, so the caller never has to compare
  # counts to know whether to offer "more".
  Page = Data.define(:entries, :next_cursor)

  def self.call(actor:, team:, cursor: nil, limit: DEFAULT_LIMIT, include_archived: false)
    new(actor: actor, team: team, cursor: cursor, limit: limit,
      include_archived: include_archived).call
  end

  def initialize(actor:, team:, cursor:, limit:, include_archived:)
    @actor = actor
    @team = team
    @cursor = cursor.presence
    @limit = limit.to_i.clamp(1, MAX_LIMIT)
    @include_archived = include_archived
  end

  def call
    # One row more than asked for: whether another page exists is a fact about
    # the data, and asking for `limit + 1` answers it without a second query and
    # without a `COUNT` over the whole set.
    rows = scope.order(:id).limit(@limit + 1).to_a

    entries = rows.first(@limit)
    next_cursor = rows.length > @limit ? Opanel::Identifier.external(:project, entries.last.id) : nil

    Page.new(entries: entries.map { |project| entry_for(project) }, next_cursor: next_cursor)
  end

  private

  attr_reader :actor, :team

  # Through `TenantScope`, so this query reads its tenancy boundary from the same
  # place every other one does (M01-04 AC5) — and then narrowed to the Team asked
  # about. Both are needed: the first decides what the actor may see at all, the
  # second which of it this page is about.
  def scope
    relation = TenantScope.for(actor, Project).relation.where(team_id: team.id)
    relation = relation.where(status: Project::ACTIVE) unless @include_archived
    relation = relation.where(Project.arel_table[:id].gt(cursor_id)) if cursor_id

    relation
  end

  def cursor_id
    return nil if @cursor.nil?

    @cursor_id ||= Opanel::Identifier.parse(:project, @cursor)
  end

  def entry_for(project)
    Entry.new(
      id: project.external_id,
      name: project.name,
      slug: project.slug,
      description: project.description,
      status: project.status,
      created_at: project.created_at
    )
  end
end
