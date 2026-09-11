# Environments of a Project, one page at a time (doc 09 §23).
#
# Like `ProjectsForTeam`, this uses keyset pagination so pages remain stable
# under concurrent inserts (M01-07 AC6). The cursor is the ULID of the last
# entry on the page.
class EnvironmentsForProject
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  Entry = Data.define(:id, :name, :slug, :type, :status, :created_at)
  Page = Data.define(:entries, :next_cursor)

  def self.call(actor:, project:, cursor: nil, limit: DEFAULT_LIMIT)
    new(actor: actor, project: project, cursor: cursor, limit: limit).call
  end

  def initialize(actor:, project:, cursor:, limit:)
    @actor = actor
    @project = project
    @cursor = cursor.presence
    @limit = limit.to_i.clamp(1, MAX_LIMIT)
  end

  def call
    rows = scope.order(:id).limit(@limit + 1).to_a
    entries = rows.first(@limit)
    next_cursor = rows.length > @limit ? Opanel::Identifier.external(:environment, entries.last.id) : nil

    Page.new(entries: entries.map { |env| entry_for(env) }, next_cursor: next_cursor)
  end

  private

  attr_reader :actor, :project

  def scope
    relation = TenantScope.for(actor, Environment).relation.where(project_id: project.id)
    relation = relation.where(Environment.arel_table[:id].gt(cursor_id)) if cursor_id

    relation
  end

  def cursor_id
    return nil if @cursor.nil?

    @cursor_id ||= Opanel::Identifier.parse(:environment, @cursor)
  end

  def entry_for(env)
    Entry.new(
      id: env.external_id,
      name: env.name,
      slug: env.slug,
      type: env.type,
      status: env.status,
      created_at: env.created_at
    )
  end
end
