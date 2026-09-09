require "openssl"

# A revocable, server-side session (doc 04 §8.2, doc 09 §15.2).
#
# Two lifetimes, because Annex C §7.1 asks for both and each covers what the
# other does not: `ABSOLUTE_TTL` ends a session that has been open too long
# however actively it is used, and `IDLE_TTL` ends one that has been abandoned
# however recently it was opened.
#
# `active?` is **derived**, never a stored boolean. A status column would have to
# be written by something, and whatever failed to write it would leave a revoked
# session granting access.
class Session < ApplicationRecord
  include UlidPrimaryKey

  ABSOLUTE_TTL = 7.days
  IDLE_TTL = 12.hours

  # `last_seen_at` is refreshed at most this often. Writing on every request
  # turns every authenticated GET into a write; the cost of the throttle is that
  # idle expiry is accurate to within one minute, which is nothing against a
  # twelve-hour window.
  LAST_SEEN_THROTTLE = 1.minute

  MFA_LEVELS = %w[password].freeze

  belongs_to :user

  validates :token_digest, presence: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :expires_at, :last_seen_at, presence: true
  validates :mfa_level, inclusion: { in: MFA_LEVELS }

  scope :unrevoked, -> { where(revoked_at: nil) }
  # Strictly greater than, matching `#active?` exactly: a scope and a predicate
  # that disagree at the boundary produce a session the query returns and the
  # object then refuses, which is a bug nobody can reproduce.
  scope :active, lambda {
    unrevoked
      .where("sessions.expires_at > ?", Time.current)
      .where("sessions.last_seen_at > ?", IDLE_TTL.ago)
  }

  # The stored form of a token. SHA-256, hex — see the migration for why this is
  # not a KDF.
  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  # 256 bits. The value exists in the response cookie and nowhere else.
  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def active?
    revoked_at.nil? && expires_at.present? && last_seen_at.present? &&
      expires_at > Time.current && last_seen_at > IDLE_TTL.ago
  end

  def revoked?
    revoked_at.present?
  end

  def stale_last_seen?
    last_seen_at.nil? || last_seen_at <= LAST_SEEN_THROTTLE.ago
  end

  # One narrow UPDATE. `update_column` on purpose: this is not the user's intent
  # changing, it is an observation being recorded, and it must not touch
  # `updated_at`, run validations or fire callbacks on the hot path of every
  # authenticated request.
  def touch_last_seen!
    update_column(:last_seen_at, Time.current)
  end

  # Idempotent: revoking an already revoked session leaves the original moment
  # in place, so "when did this stop working" stays answerable.
  def revoke!
    return true if revoked?

    update_column(:revoked_at, Time.current)
  end
end
