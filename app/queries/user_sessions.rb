# The caller's own sessions, as the account page needs them (doc 04 §8.2, AC5).
#
# A Query Object rather than a scope because the read is not the model's shape:
# it selects a **subset of columns**, projects them into value objects and
# decides an ordering the page depends on. `token_digest` is never selected, so
# it cannot reach a prop by accident — the safest way to keep a credential out of
# a response is for the response to never have loaded it.
class UserSessions
  # Pagination is mandatory for a potentially large collection. A hundred devices
  # is already implausible; an unbounded load is not a read, it is a way to make
  # the page fail for the one account that has ten thousand rows.
  LIMIT = 100

  COLUMNS = %i[id user_id expires_at last_seen_at revoked_at ip_address user_agent created_at].freeze

  # Active first, then newest first. Written as one SQL ordering so the database
  # does it once, rather than loading everything and sorting in Ruby.
  ORDER = "(sessions.revoked_at IS NULL) DESC, sessions.created_at DESC, sessions.id DESC"

  Entry = Data.define(
    :id, :current, :active, :ip_address, :user_agent,
    :last_seen_at, :created_at, :expires_at, :revoked_at
  )

  def self.call(user:, current_session_id: nil)
    new(user: user, current_session_id: current_session_id).call
  end

  def initialize(user:, current_session_id: nil)
    @user = user
    @current_session_id = current_session_id
  end

  def call
    user.sessions.select(*COLUMNS).order(Arel.sql(ORDER)).limit(self.class::LIMIT).map do |session|
      Entry.new(
        id: session.external_id,
        current: session.id == current_session_id,
        active: session.active?,
        ip_address: session.ip_address&.to_s,
        user_agent: session.user_agent,
        last_seen_at: session.last_seen_at,
        created_at: session.created_at,
        expires_at: session.expires_at,
        revoked_at: session.revoked_at
      )
    end
  end

  private

  attr_reader :user, :current_session_id
end
