# Keyset pagination of Services in an Environment (doc 10 UC-013).
#
# Like EnvironmentsForProject, this query returns a cursor-based paginated list,
# where the cursor is the ULID of the last Service in the previous page.
#
class ServicesForEnvironment
  LIMIT_MIN = 1
  LIMIT_MAX = 100
  LIMIT_DEFAULT = 20

  def self.call(actor:, environment:, cursor: nil, limit: LIMIT_DEFAULT)
    new(actor: actor, environment: environment, cursor: cursor, limit: limit).call
  end

  def initialize(actor:, environment:, cursor:, limit:)
    @actor = actor
    @environment = environment
    @cursor = cursor
    @limit = Integer(limit || LIMIT_DEFAULT)
  end

  def call
    limit = [ LIMIT_MIN, [ @limit, LIMIT_MAX ].min ].max

    # Start with services in this environment, ordered by ULID (keyset pagination).
    query = environment.services.kept.order(id: :asc)

    # If a cursor is provided, start after that ULID.
    if cursor.present?
      cursor_id = Opanel::Identifier.parse(:service, cursor)
      query = query.where("id > ?", cursor_id)
    end

    # Fetch limit + 1 to know if there are more results.
    entries = query.limit(limit + 1).to_a

    # If we got more than the requested limit, we have more; cut to limit and
    # return the next cursor.
    has_more = entries.size > limit
    entries = entries.first(limit)

    next_cursor = has_more ? entries.last&.external_id : nil

    Opanel::Result.success(PagedResult.new(entries, next_cursor))
  rescue Opanel::Identifier::InvalidIdentifier
    Opanel::Result.failure(code: "INVALID_CURSOR", message: "The cursor is invalid.")
  end

  class PagedResult
    attr_reader :entries, :next_cursor

    def initialize(entries, next_cursor)
      @entries = entries
      @next_cursor = next_cursor
    end
  end
end
