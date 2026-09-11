# The human identity of the installation (doc 09 §3.1).
#
# There is no `password` attribute and there must not be one: nothing on this
# object can hold a plaintext credential, so no serializer, log line, error
# report or `inspect` can leak one by accident. Hashing lives in
# `Opanel::PasswordHashing`; the digest is the only form the credential takes
# here (Annex C §7.1, AC2).
class User < ApplicationRecord
  include UlidPrimaryKey

  # ACTIVE authenticates. SUSPENDED and DELETED_PENDING do not, and
  # DELETED_PENDING is terminal for authentication — the address it holds stays
  # reserved, which is why the unique index on `email` is unconditional.
  STATUSES = %w[ACTIVE SUSPENDED DELETED_PENDING].freeze
  AUTHENTICATABLE_STATUSES = %w[ACTIVE].freeze

  EMAIL_FORMAT = /\A[^@\s]+@[^@\s.]+(\.[^@\s.]+)+\z/
  EMAIL_MAX_LENGTH = 254
  DISPLAY_NAME_MAX_LENGTH = 120

  has_many :sessions, dependent: :destroy

  validates :email, presence: true, length: { in: 3..EMAIL_MAX_LENGTH }, format: { with: EMAIL_FORMAT }
  validates :display_name, presence: true, length: { maximum: DISPLAY_NAME_MAX_LENGTH }
  validates :password_digest, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :authenticatable, -> { where(status: AUTHENTICATABLE_STATUSES) }

  # The address is normalized on the way in as well as being `citext` on the way
  # out. The column decides equality; this decides what is stored, so a stray
  # space cannot become part of an identity.
  def self.normalize_email(value)
    value.to_s.strip.downcase.presence
  end

  def authenticatable?
    AUTHENTICATABLE_STATUSES.include?(status)
  end
end
