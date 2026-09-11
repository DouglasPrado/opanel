require "rails_helper"

# The invariants of the entity itself (doc 09 §3.3). What the *installation*
# guarantees — one bootstrap, at least one administrator — is proved against real
# PostgreSQL in `spec/integration/`.
RSpec.describe InstanceRole, type: :unit do
  describe "the roles it recognises" do
    it "accepts the three of doc 09 §3.3" do
      expect(described_class::ROLES).to eq(%w[INSTANCE_ADMIN INSTANCE_OPERATOR INSTANCE_AUDITOR])
    end

    it "refuses anything else" do
      role = build(:instance_role, role: "INSTANCE_SUPERUSER")

      expect(role.valid?).to be(false)
      expect(role.errors[:role]).to be_present
    end
  end

  describe "the bootstrap marker" do
    it "belongs to INSTANCE_ADMIN and to nothing else" do
      role = build(:instance_role, :operator, granted_by_bootstrap: true)

      expect(role.valid?).to be(false)
      expect(role.errors[:granted_by_bootstrap].join).to match(/INSTANCE_ADMIN/)
    end

    it "is accepted on an INSTANCE_ADMIN grant" do
      expect(build(:instance_role, :bootstrap).valid?).to be(true)
    end
  end

  describe "#active?" do
    it "is true while `revoked_at` is unset" do
      expect(build(:instance_role).active?).to be(true)
    end

    it "is false once revoked" do
      expect(build(:instance_role, :revoked).active?).to be(false)
    end
  end

  describe ".bootstrapped?" do
    it "is false on an installation that never completed one" do
      create(:instance_role)

      expect(described_class.bootstrapped?).to be(false)
    end

    it "is true once the bootstrap grant exists" do
      create(:instance_role, :bootstrap)

      expect(described_class.bootstrapped?).to be(true)
    end

    # Revoking the grant does not un-bootstrap the installation: it records that
    # the first registration happened, and that stays true afterwards.
    it "stays true after the bootstrap grant is revoked" do
      create(:instance_role, :bootstrap, revoked_at: Time.current)

      expect(described_class.bootstrapped?).to be(true)
    end
  end

  describe ".active_admin_count" do
    it "counts only active INSTANCE_ADMIN grants" do
      create(:instance_role)
      create(:instance_role, :revoked)
      create(:instance_role, :operator)

      expect(described_class.active_admin_count).to eq(1)
    end
  end
end
