# Whether the installation has been bootstrapped, and who administers it.
#
# The question "is this a fresh installation?" is answered by the presence of the
# bootstrap grant, not by `User.count.zero?`. The two differ exactly when they
# matter: a registration that lost the bootstrap race leaves users in the table
# while the grant still records which one completed the installation.
#
# This is a read. It is deliberately **not** what `BootstrapInstallation` consults
# before writing — see that class for why a read cannot decide a race.
class InstallationBootstrapState
  def self.call
    new.call
  end

  def call
    Opanel::Result.success(
      bootstrapped: InstanceRole.bootstrapped?,
      administrator_count: InstanceRole.active_admin_count,
      bootstrapped_at: bootstrap_grant&.created_at,
      bootstrapped_by: bootstrap_grant&.user&.external_id
    )
  end

  private

  def bootstrap_grant
    return @bootstrap_grant if defined?(@bootstrap_grant)

    @bootstrap_grant = InstanceRole.bootstrap.includes(:user).first
  end
end
