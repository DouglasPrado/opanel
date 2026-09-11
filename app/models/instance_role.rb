# A role over the *installation*, held by a User (doc 09 §3.3).
#
# Separate from `TeamMember` on purpose: doc 04 §7.1 draws the line between
# administering the installation and owning a tenant, and keeping the two in
# different tables is what makes "transferring TEAM_OWNER does not transfer
# INSTANCE_ADMIN" (§7.1) structurally true — the transfer of M11-03 touches
# `team_members` and cannot reach this table at all.
#
# The row outlives the grant: revoking sets `revoked_at` rather than deleting, so
# who administered the installation and until when stays answerable.
class InstanceRole < ApplicationRecord
  include UlidPrimaryKey

  ROLES = %w[INSTANCE_ADMIN INSTANCE_OPERATOR INSTANCE_AUDITOR].freeze

  ADMIN = "INSTANCE_ADMIN"

  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validate :bootstrap_marker_is_reserved_for_admin

  scope :active, -> { where(revoked_at: nil) }
  scope :admins, -> { where(role: ADMIN) }
  scope :bootstrap, -> { where(granted_by_bootstrap: true) }

  # Whether the installation has been bootstrapped, asked of the fact rather than
  # of a counter: the bootstrap grant is the record that the first registration
  # happened, and `index_instance_roles_single_bootstrap` guarantees there is at
  # most one. Revoking it later does not un-bootstrap the installation, so this
  # deliberately ignores `revoked_at`.
  def self.bootstrapped?
    bootstrap.exists?
  end

  def self.active_admin_count
    active.admins.count
  end

  def active?
    revoked_at.nil?
  end

  private

  # Mirrors `instance_roles_bootstrap_is_admin`. The database is the enforcement;
  # this turns the violation into a message instead of a raised PG error.
  def bootstrap_marker_is_reserved_for_admin
    return if granted_by_bootstrap.blank?
    return if role == ADMIN

    errors.add(:granted_by_bootstrap, "marks the bootstrap grant, which is #{ADMIN}")
  end
end
