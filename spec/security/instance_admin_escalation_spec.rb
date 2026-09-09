require "rails_helper"

# "Somente o bootstrap concede INSTANCE_ADMIN automaticamente. Não existe caminho
# alternativo de auto-promoção" — the Story's Security Requirements, checked from
# the outside.
#
# The claim has two halves and both are asserted: no *route* reaches the grant, and
# no *path through the application layer* grants it to somebody who did not already
# administer the installation.
RSpec.describe "escalation to INSTANCE_ADMIN", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }

  def register(email)
    RegisterUser.call(email: email, display_name: "Somebody", password: password,
      ip: "203.0.113.1", user_agent: "rspec")
  end

  describe "the routes of this Milestone" do
    # M11-12 owns the instance administration area. Until it exists, no HTTP path
    # may reach an instance role at all — asserted against the real route set
    # rather than by reading the routes file.
    it "expose no path that grants or revokes one" do
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

      expect(paths.grep(/instance/i)).to be_empty
      expect(paths.grep(/admin/i)).to be_empty
    end
  end

  describe "a user who is not an instance administrator" do
    let!(:bootstrap) { register("first@example.test") }
    let(:outsider) { register("outsider@example.test").value[:user] }

    it "cannot grant themselves INSTANCE_ADMIN" do
      result = GrantInstanceRole.call(actor: outsider, user: outsider, role: "INSTANCE_ADMIN")

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(InstanceRole.where(user_id: outsider.id)).not_to exist
    end

    it "cannot become one by creating a Team" do
      CreateTeam.call(actor: outsider, name: "Their Own Team")

      expect(InstanceRole.where(user_id: outsider.id)).not_to exist
      expect(InstanceRole.active.admins.count).to eq(1)
    end

    it "cannot become one by registering again" do
      second = register("outsider-again@example.test")

      expect(second.value[:bootstrapped]).to be(false)
      expect(InstanceRole.bootstrap.count).to eq(1)
    end
  end

  describe "the bootstrap grant" do
    let!(:bootstrap) { register("first@example.test") }

    # The singleton index is the enforcement. Bypassing the application entirely
    # still cannot produce a second bootstrap grant, which is what makes "only the
    # bootstrap grants it" a property of the installation rather than of the code
    # path somebody happened to use.
    it "cannot be duplicated even with the application bypassed" do
      other = register("other@example.test").value[:user]

      expect {
        InstanceRole.insert_all!([ {
          id: Opanel::Identifier.generate, user_id: other.id, role: "INSTANCE_ADMIN",
          granted_by_bootstrap: true, created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_instance_roles_single_bootstrap/)
    end

    it "cannot be moved onto a lesser role, so it cannot occupy the slot for free" do
      expect {
        InstanceRole.insert_all!([ {
          id: Opanel::Identifier.generate, user_id: create(:user).id, role: "INSTANCE_OPERATOR",
          granted_by_bootstrap: true, created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /instance_roles_bootstrap_is_admin/)
    end
  end

  describe "what is written about instance roles" do
    let!(:bootstrap) { register("first@example.test") }

    it "logs the actor and the role, and no credential" do
      administrator = bootstrap.value[:user]
      target = register("target@example.test").value[:user]

      logs = capture_logs do
        GrantInstanceRole.call(actor: administrator, user: target, role: "INSTANCE_AUDITOR")
      end

      expect(logs).to include("instance_role.granted")
      expect(logs).to include("INSTANCE_AUDITOR")
      expect(logs).not_to include(password)
      expect(logs).not_to include(administrator.password_digest)
    end
  end
end
