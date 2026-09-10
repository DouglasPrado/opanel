require "rails_helper"

# AC9 — bootstrap requires INSTANCE_ADMIN — and the cross-team denial Annex C
# §7.3 requires of every mutation.
#
# The interesting property is that bootstrapping needs **two** authorities at
# once: doc 04 §6.2's "Adicionar/remover Cluster" inside the Team, and doc 04
# §7.1's separate administration of the installation. Neither alone is enough,
# and each example below removes exactly one of them.
RSpec.describe "Cluster authorization", :integration do
  let(:team) { create(:team) }
  let(:cluster) { create(:cluster, team: team) }

  def member(role, of: team)
    user = create(:user)
    create(:team_member, team: of, user: user, role: role, status: "ACTIVE")
    user
  end

  def administrator(user)
    InstanceRole.create!(user: user, role: InstanceRole::ADMIN)
    user
  end

  describe "bootstrapping (AC9)" do
    it "permits an OWNER who is also an instance administrator" do
      actor = administrator(team.owner)

      expect(ClusterPolicy.new(actor, cluster).bootstrap?).to be(true)
    end

    it "permits an ADMIN who is also an instance administrator" do
      actor = administrator(member("ADMIN"))

      expect(ClusterPolicy.new(actor, cluster).bootstrap?).to be(true)
    end

    # The Team half alone. This is the case doc 04 §7.1 exists to separate: owning
    # a tenant is not administering the installation.
    it "refuses an OWNER with no instance role, naming the missing role" do
      decision = ClusterPolicy.new(team.owner, cluster).decide(:bootstrap)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:instance_role_required)
    end

    # The installation half alone. An INSTANCE_ADMIN is not automatically
    # anything inside somebody's Team.
    it "refuses an instance administrator with no membership of the Team" do
      actor = administrator(create(:user))

      decision = ClusterPolicy.new(actor, cluster).decide(:bootstrap)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:no_membership)
    end

    # The role half, inside the Team, with the instance role held.
    it "refuses a DEVELOPER even when they administer the installation" do
      actor = administrator(member("DEVELOPER"))

      decision = ClusterPolicy.new(actor, cluster).decide(:bootstrap)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:insufficient_role)
    end

    it "refuses a VIEWER" do
      expect(ClusterPolicy.new(administrator(member("VIEWER")), cluster).bootstrap?).to be(false)
    end

    # Revoking takes effect on the very next decision, with nothing to
    # invalidate — the same property membership suspension has.
    it "refuses once the instance role is revoked" do
      actor = administrator(team.owner)
      expect(ClusterPolicy.new(actor, cluster).bootstrap?).to be(true)

      InstanceRole.active.where(user_id: actor.id).update_all(revoked_at: Time.current)

      expect(ClusterPolicy.new(actor, cluster).bootstrap?).to be(false)
    end

    # An instance role that is not ADMIN does not open the door.
    it "refuses an INSTANCE_OPERATOR" do
      actor = team.owner
      InstanceRole.create!(user: actor, role: "INSTANCE_OPERATOR")

      expect(ClusterPolicy.new(actor, cluster).bootstrap?).to be(false)
    end
  end

  describe "reading" do
    %w[OWNER ADMIN DEVELOPER VIEWER].each do |role|
      it "permits a #{role} of the Team, with no instance role" do
        actor = role == "OWNER" ? team.owner : member(role)

        expect(ClusterPolicy.new(actor, cluster).view?).to be(true)
      end
    end

    it "refuses somebody with no membership" do
      expect(ClusterPolicy.new(create(:user), cluster).view?).to be(false)
    end

    it "refuses a nil actor" do
      expect(ClusterPolicy.new(nil, cluster).view?).to be(false)
    end
  end

  # Refreshing writes only observed state. A VIEWER looking at a stale reading
  # should be able to ask for a current one; that is what a derived status is for.
  describe "refreshing" do
    it "permits a VIEWER" do
      expect(ClusterPolicy.new(member("VIEWER"), cluster).refresh?).to be(true)
    end

    it "refuses somebody from another Team" do
      expect(ClusterPolicy.new(create(:team).owner, cluster).refresh?).to be(false)
    end
  end

  describe "deny by default" do
    it "raises for an action nobody registered" do
      expect { ClusterPolicy.permitted_roles(:drain_node) }
        .to raise_error(ApplicationPolicy::UnregisteredAction, /drain_node/)
    end

    it "denies an unregistered action rather than allowing it" do
      decision = ClusterPolicy.new(administrator(team.owner), cluster).decide(:drain_node)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:unregistered_action)
    end
  end

  # Reuse asserted, not assumed: a copy of doc 04 §6.2's rows would be correct on
  # the day it was written and stale afterwards.
  describe "the rules are references to TeamPolicy, not copies" do
    it "reads bootstrap and view from the same table TeamPolicy declares" do
      expect(ClusterPolicy::PERMISSIONS[:bootstrap]).to equal(TeamPolicy::PERMISSIONS[:manage_clusters])
      expect(ClusterPolicy::PERMISSIONS[:view]).to equal(TeamPolicy::PERMISSIONS[:view])
    end
  end

  # AC: nobody outside the Team reads or mutates, and the tenancy boundary is
  # what makes the refusal indistinguishable from absence.
  describe "cross-team" do
    let(:outsider) { administrator(create(:team).owner) }

    it "refuses to read, even to an instance administrator" do
      expect(ClusterPolicy.new(outsider, cluster).view?).to be(false)
    end

    it "refuses to bootstrap into a Team the actor does not belong to" do
      expect(ClusterPolicy.new(outsider, Cluster.new(team: team)).bootstrap?).to be(false)
    end

    it "cannot reach the Cluster through the tenancy boundary either" do
      expect(TenantScope.for(outsider, Cluster).find(cluster.id)).to be_nil
    end

    it "records the denial in the audit trail with the classified reason" do
      expect {
        Opanel::Authorization.authorize(outsider, :view, cluster)
      }.to change { AuditLog.where(action: "authorization.denied").count }.by(1)

      expect(AuditLog.where(action: "authorization.denied").last.after)
        .to eq({ "reason" => "no_membership" })
    end

    # The instance-role denial is recorded too, and with its own reason — a trail
    # saying "outside your scope" about a missing instance role sends somebody
    # looking in the wrong table.
    it "records a missing instance role as its own reason, not as a scope problem" do
      Opanel::Authorization.authorize(team.owner, :bootstrap, cluster)

      expect(AuditLog.where(action: "authorization.denied").last.after)
        .to eq({ "reason" => "instance_role_required" })
    end
  end
end
