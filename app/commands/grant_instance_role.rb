# Grants an instance role to a user. Only an active INSTANCE_ADMIN may do it
# (AC6), and the grant is never the bootstrap one — that marker belongs to
# `BootstrapInstallation` alone, which is what "somente o bootstrap concede
# INSTANCE_ADMIN automaticamente" (doc 04 §3.1) means in code.
#
# There is no self-promotion path: the actor must already hold INSTANCE_ADMIN to
# grant anything, so the only way the first one exists is the bootstrap.
class GrantInstanceRole
  def self.call(actor:, user:, role:)
    new(actor: actor, user: user, role: role).call
  end

  def initialize(actor:, user:, role:)
    @actor = actor
    @user = user
    @role = role.to_s
  end

  def call
    return failure("FORBIDDEN", "Only an instance administrator may grant instance roles.") unless
      administrator?(actor)
    return failure("VALIDATION_ERROR", "Unknown instance role.") unless
      InstanceRole::ROLES.include?(role)

    grant = InstanceRole.create!(user: user, role: role)

    Rails.logger.info(event: "instance_role.granted", actor_id: actor.external_id,
      user_id: user.external_id, role: role, result: "succeeded")

    Opanel::Result.success(instance_role: grant)
  rescue ActiveRecord::RecordNotUnique
    # The user already holds this role, actively. Idempotent from the caller's
    # point of view: the intended state is the state.
    Opanel::Result.success(instance_role: InstanceRole.active.find_by(user: user, role: role))
  end

  private

  attr_reader :actor, :user, :role

  def administrator?(candidate)
    return false unless candidate.respond_to?(:id)

    InstanceRole.active.admins.where(user_id: candidate.id).exists?
  end

  def failure(code, message)
    Rails.logger.info(event: "instance_role.granted", actor_id: actor.try(:external_id),
      role: role, result: "denied")

    Opanel::Result.failure(code: code, message: message)
  end
end
