require "rails_helper"

# AC5: revoking the last active INSTANCE_ADMIN is blocked, so an installation
# cannot be left without anybody able to administer it.
RSpec.describe "revoking an instance role", type: :integration do
  let(:admin) { create(:user) }
  let!(:admin_grant) { create(:instance_role, :bootstrap, user: admin) }

  describe "the last active administrator (AC5)" do
    it "is refused, with a stable error" do
      result = RevokeInstanceRole.call(actor: admin, instance_role: admin_grant)

      expect(result).to be_failure
      expect(result.code).to eq("INVALID_STATE_TRANSITION")
      expect(result.message).to match(/without an administrator/i)
      expect(admin_grant.reload.revoked_at).to be_nil
      expect(InstanceRole.active_admin_count).to eq(1)
    end

    # The refusal is about the last *administrator*, not about the bootstrap
    # marker: once a second admin exists the first one can step down, and the
    # installation stays administrable.
    it "is allowed once a second administrator exists" do
      second = create(:user)
      create(:instance_role, user: second)

      result = RevokeInstanceRole.call(actor: admin, instance_role: admin_grant)

      expect(result).to be_success
      expect(admin_grant.reload.revoked_at).to be_present
      expect(InstanceRole.active_admin_count).to eq(1)
    end

    it "does not count a revoked grant as an administrator" do
      other = create(:user)
      create(:instance_role, :revoked, user: other)

      result = RevokeInstanceRole.call(actor: admin, instance_role: admin_grant)

      expect(result).to be_failure
      expect(result.code).to eq("INVALID_STATE_TRANSITION")
    end

    # A non-admin role is not what keeps the installation administrable, so its
    # revocation is never the one that empties it.
    it "allows revoking a non-admin role even when one administrator remains" do
      operator = create(:user)
      grant = create(:instance_role, :operator, user: operator)

      result = RevokeInstanceRole.call(actor: admin, instance_role: grant)

      expect(result).to be_success
      expect(grant.reload.revoked_at).to be_present
    end
  end

  describe "who may revoke" do
    it "refuses an actor without INSTANCE_ADMIN (AC6)" do
      outsider = create(:user)
      operator_grant = create(:instance_role, :operator, user: create(:user))

      result = RevokeInstanceRole.call(actor: outsider, instance_role: operator_grant)

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(operator_grant.reload.revoked_at).to be_nil
    end
  end

  describe "revoking twice" do
    it "is idempotent rather than an error" do
      second = create(:user)
      grant = create(:instance_role, user: second)

      expect(RevokeInstanceRole.call(actor: admin, instance_role: grant)).to be_success
      first_revoked_at = grant.reload.revoked_at

      expect(RevokeInstanceRole.call(actor: admin, instance_role: grant)).to be_success
      expect(grant.reload.revoked_at).to eq(first_revoked_at)
    end
  end
end
