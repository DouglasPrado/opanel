require "rails_helper"

# Authorization for a Service against doc 04 §6.2 (AC11: audit and Policy).
RSpec.describe ServicePolicy, type: :policy do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  def context_for(role:)
    if role == "OWNER"
      { actor: team.owner, resource: service }
    else
      user = create(:user)
      create(:team_member, role: role, team: team, user: user, status: "ACTIVE")
      { actor: user, resource: service }
    end
  end

  def deny_context_for(role:)
    # Create a different team where the actor is a member (but not of the service's team)
    other_team = create(:team)
    if role == "OWNER"
      # The other team's owner tries to access this team's service
      { actor: other_team.owner, resource: service }
    else
      # A non-owner member of another team tries to access this team's service
      user = create(:user)
      create(:team_member, role: role, team: other_team, user: user, status: "ACTIVE")
      { actor: user, resource: service }
    end
  end

  describe "#view?" do
    it "grants access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).view?).to be false
    end
  end

  describe "#create?" do
    let(:new_service) { Service.new(environment: environment, team: team) }

    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], new_service).create?).to be false
    end
  end

  describe "#update?" do
    it "denies access to VIEWER" do
      ctx = context_for(role: "VIEWER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end

    it "grants access to DEVELOPER" do
      ctx = context_for(role: "DEVELOPER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to ADMIN" do
      ctx = context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "grants access to OWNER" do
      ctx = context_for(role: "OWNER")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be true
    end

    it "denies access to a member of another Team" do
      ctx = deny_context_for(role: "ADMIN")
      expect(ServicePolicy.new(ctx[:actor], ctx[:resource]).update?).to be false
    end
  end

  # M01-18. The reconciler adds no user-facing mutation — it converges what a
  # Command already authorized — but it does add a resource an operator can read
  # about, and reading across a tenant boundary is the failure that matters here.
  # The tenancy of a reconcile is the Service's own Team, in the lease, in the
  # ReconciliationRun and in the audit row.
  describe "what a reconcile leaves behind, across Teams" do
    let!(:network) do
      create(:network, environment: environment, team: team, cluster: environment.cluster,
        swarm_network_id: "abc123", status: Network::READY)
    end

    before do
      service.update!(image_digest: "sha256:#{'a' * 64}", image_ref: "docker.io/busybox:latest",
        status: Service::PROVISIONING)
      observed = service_observation(service)
      ServiceReconciler.call(service: service, executor: FakeSwarmExecutor.new(
        "inspect_service" => [ not_found, applied(observed) ],
        "create_service" => applied(observed),
        "list_tasks" => tasks
      ))
    end

    it "is not visible to another Team through the tenant-scoped query" do
      outsider = deny_context_for(role: "ADMIN")[:actor]

      expect(TenantScope.for(outsider, Service).find(service.id)).to be_nil
      expect(TenantScope.for(outsider, ReconciliationRun).relation.where(resource_id: service.id))
        .to be_empty
    end

    it "is visible to a member of the Service's own Team" do
      insider = context_for(role: "VIEWER")[:actor]

      expect(TenantScope.for(insider, Service).find(service.id)).to eq(service)
      expect(TenantScope.for(insider, ReconciliationRun).relation.where(resource_id: service.id))
        .to be_present
    end

    it "records the reconcile under the Service's Team and no other" do
      expect(ReconciliationRun.for_resource("Service", service.id).pluck(:team_id).uniq).to eq([ team.id ])
      expect(AuditLog.for_resource("Service", service.id).pluck(:team_id).uniq).to eq([ team.id ])
      expect(ResourceLock.find_by(scope_key: "service:#{service.id}").team_id).to eq(team.id)
    end
  end
end
