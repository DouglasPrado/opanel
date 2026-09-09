require "openssl"

# The counter behind the login and registration throttle (Annex C §7.1, AC7).
#
# Counting happens in **one statement**. A read-then-write would need a lock the
# login path cannot afford, and without one two racing requests both read the
# same count and both decide they are under the limit — which is precisely the
# concurrency a credential-stuffing run produces.
class AuthenticationAttempt < ApplicationRecord
  include UlidPrimaryKey

  SCOPES = %w[login_email login_ip registration_ip].freeze

  # The address runs out before the IP does, on purpose: one attacker hammering
  # one account must not be able to lock out everyone else behind a shared
  # egress address.
  LIMITS = {
    "login_email" => { threshold: 10, window: 15.minutes },
    "login_ip" => { threshold: 30, window: 15.minutes },
    "registration_ip" => { threshold: 5, window: 1.hour }
  }.freeze

  # Rows whose window closed this long ago carry no information.
  RETENTION = 1.day

  validates :scope, inclusion: { in: SCOPES }
  validates :attempt_count, numericality: { greater_than_or_equal_to: 0 }

  # The key is hashed before it is stored. See the migration: an enumerable list
  # of the addresses that have tried to sign in is a disclosure by itself.
  def self.digest(key)
    OpenSSL::Digest::SHA256.hexdigest(key.to_s.strip.downcase)
  end

  def self.limit_for(scope)
    LIMITS.fetch(scope.to_s)
  end

  # Records one attempt and returns the count inside the current window.
  #
  # `ON CONFLICT ... DO UPDATE` with the window reset expressed in the statement:
  # a row whose window has closed restarts at 1 rather than being reset by a
  # second round trip that another request could interleave with.
  def self.record(scope:, key:, now: Time.current)
    floor = connection.quote(now - limit_for(scope).fetch(:window))

    result = upsert_all(
      [ {
        id: Opanel::Identifier.generate,
        scope: scope.to_s,
        key_digest: digest(key),
        window_started_at: now,
        attempt_count: 1,
        created_at: now,
        updated_at: now
      } ],
      unique_by: %i[scope key_digest],
      # The window reset is expressed inside the statement rather than as a
      # second round trip another request could interleave with. Nothing here is
      # user input: `floor` is derived from the clock and quoted by the adapter,
      # and every other value arrives through `excluded`.
      on_duplicate: Arel.sql(<<~SQL.squish),
        attempt_count = CASE
          WHEN authentication_attempts.window_started_at <= #{floor} THEN 1
          ELSE authentication_attempts.attempt_count + 1 END,
        window_started_at = CASE
          WHEN authentication_attempts.window_started_at <= #{floor} THEN excluded.window_started_at
          ELSE authentication_attempts.window_started_at END,
        updated_at = excluded.updated_at
      SQL
      returning: %w[attempt_count]
    )

    result.first.fetch("attempt_count")
  end

  # Whether this key is over its threshold right now. Read-only: recording an
  # attempt is a separate, explicit call, so a check never inflates the count it
  # is checking.
  def self.exceeded?(scope:, key:)
    find_by(scope: scope.to_s, key_digest: digest(key))&.exceeded? || false
  end

  # Called after a successful authentication, inside the same transaction that
  # opens the session.
  def self.clear(scope:, key:)
    where(scope: scope.to_s, key_digest: digest(key)).delete_all
  end

  # Housekeeping, called from the same code path rather than from a new
  # recurring job: the table is only ever read by key, so a stale row costs
  # nothing until it is swept.
  def self.sweep(now: Time.current)
    oldest_window = LIMITS.values.map { |limit| limit.fetch(:window) }.max

    where(window_started_at: ...(now - oldest_window - RETENTION)).delete_all
  end

  def window_open?(now: Time.current)
    window_started_at.present? && window_started_at > now - self.class.limit_for(scope).fetch(:window)
  end

  def exceeded?(now: Time.current)
    window_open?(now: now) && attempt_count >= self.class.limit_for(scope).fetch(:threshold)
  end
end
