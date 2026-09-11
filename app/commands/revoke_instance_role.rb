# Revokes an instance role, refusing to leave the installation without an
# administrator (AC5).
#
# ## Why a lock and not a constraint
#
# "At least one active INSTANCE_ADMIN must remain" is a condition over the rows
# that *survive* the write. No unique index expresses it — a unique index refuses
# a duplicate, not a last deletion — and the alternatives that would (a trigger, a
# materialised counter) each carry a cost this Story should not pay: the Ruby
# schema dumper emits no triggers, so a trigger would vanish from every database
# created from `db/schema.rb`, which is the defect recorded as SC-17 and the
# reason M01-02 chose a foreign key over one.
#
# So the active admin grants are taken under `FOR UPDATE`, **in `id` order**, before
# anything else is locked. Two concurrent revocations of the last two admins then
# queue for the same rows in the same sequence: the first commits, the second
# re-reads and sees one admin left — itself — and is refused. Without the lock both
# would read two and both would commit, leaving an installation nobody can
# administer; with the lock taken in the wrong order they deadlock instead, which
# is why the ordering is written down rather than left to chance.
#
# The Story asks for "rejeitada com erro estável", not for the database to raise,
# so a refusal here is a `Result.failure` a caller can render.
class RevokeInstanceRole
  def self.call(actor:, instance_role:)
    new(actor: actor, instance_role: instance_role).call
  end

  def initialize(actor:, instance_role:)
    @actor = actor
    @instance_role = instance_role
  end

  def call
    return failure("FORBIDDEN", "Only an instance administrator may revoke instance roles.") unless
      administrator?(actor)

    ApplicationRecord.transaction do
      # The admin grants are locked **first**, in `id` order, and that ordering is
      # the whole point. Locking this grant and then asking for the survivors
      # inverts the order between two concurrent revocations — A holds itself and
      # wants B while B holds itself and wants A — which is a deadlock, not a
      # refusal. It reproduced 6 times out of 6: one caller got the correct
      # refusal and the other got an unhandled `ActiveRecord::Deadlocked`, which
      # is not the "erro estável" the Story asks for.
      #
      # Taking the whole admin set in a fixed order means both transactions queue
      # for the same rows in the same sequence, so one simply waits and then reads
      # what the other committed.
      admin_ids = InstanceRole.active.admins.order(:id).lock.pluck(:id)

      # Re-read inside the transaction: the grant may have been revoked between
      # the caller reading it and this point. An admin grant is already locked by
      # the statement above, so this adds no new lock and cannot invert anything.
      grant = InstanceRole.lock.find_by(id: instance_role.id)

      return failure("NOT_FOUND", "That instance role does not exist.") if grant.nil?
      return Opanel::Result.success(instance_role: grant) unless grant.active?

      if grant.role == InstanceRole::ADMIN && (admin_ids - [ grant.id ]).empty?
        return failure("INVALID_STATE_TRANSITION",
          "The installation would be left without an administrator. Grant another one first.")
      end

      grant.update!(revoked_at: Time.current)

      Rails.logger.info(event: "instance_role.revoked", actor_id: actor.external_id,
        user_id: grant.user.external_id, role: grant.role, result: "succeeded")

      Opanel::Result.success(instance_role: grant)
    end
  end

  private

  attr_reader :actor, :instance_role

  def administrator?(candidate)
    return false unless candidate.respond_to?(:id)

    InstanceRole.active.admins.where(user_id: candidate.id).exists?
  end

  def failure(code, message)
    Rails.logger.info(event: "instance_role.revoked", actor_id: actor.try(:external_id),
      result: "denied", reason: code)

    Opanel::Result.failure(code: code, message: message)
  end
end
