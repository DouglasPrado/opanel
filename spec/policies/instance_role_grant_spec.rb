require "rails_helper"

# AC6: a user without INSTANCE_ADMIN cannot grant an instance role to anybody.
#
# There is no Policy class yet — RBAC is M01-04 — so the rule lives in the Command
# and is asserted here through it. That is deliberate: inventing a
# `InstanceRolePolicy` with a single caller ahead of the Story that owns the
# authorization layer would be the speculative abstraction AGENT_RULES rules out.
RSpec.describe "who may grant an instance role", type: :policy do
  let(:administrator) { create(:user) }
  let!(:administrator_grant) { create(:instance_role, :bootstrap, user: administrator) }
  let(:target) { create(:user) }

  it "allows an active INSTANCE_ADMIN" do
    result = GrantInstanceRole.call(actor: administrator, user: target, role: "INSTANCE_OPERATOR")

    expect(result).to be_success
    expect(InstanceRole.active.where(user_id: target.id, role: "INSTANCE_OPERATOR")).to exist
  end

  it "refuses an ordinary user" do
    ordinary = create(:user)

    result = GrantInstanceRole.call(actor: ordinary, user: target, role: "INSTANCE_ADMIN")

    expect(result).to be_failure
    expect(result.code).to eq("FORBIDDEN")
    expect(InstanceRole.where(user_id: target.id)).not_to exist
  end

  it "refuses a TEAM_OWNER who is not an instance administrator" do
    owner = create(:user)
    create(:team, owner: owner)

    result = GrantInstanceRole.call(actor: owner, user: target, role: "INSTANCE_ADMIN")

    expect(result).to be_failure
    expect(result.code).to eq("FORBIDDEN")
    expect(InstanceRole.where(user_id: target.id)).not_to exist
  end

  it "refuses an administrator whose grant has been revoked" do
    former = create(:user)
    create(:instance_role, :revoked, user: former)

    result = GrantInstanceRole.call(actor: former, user: target, role: "INSTANCE_OPERATOR")

    expect(result).to be_failure
    expect(result.code).to eq("FORBIDDEN")
  end

  it "refuses an unknown role" do
    result = GrantInstanceRole.call(actor: administrator, user: target, role: "INSTANCE_ROOT")

    expect(result).to be_failure
    expect(result.code).to eq("VALIDATION_ERROR")
  end

  it "is idempotent when the role is already held" do
    GrantInstanceRole.call(actor: administrator, user: target, role: "INSTANCE_AUDITOR")

    expect {
      expect(GrantInstanceRole.call(actor: administrator, user: target, role: "INSTANCE_AUDITOR"))
        .to be_success
    }.not_to change { InstanceRole.active.where(user_id: target.id).count }
  end
end
