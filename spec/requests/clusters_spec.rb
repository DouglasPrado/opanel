require "rails_helper"

# The Clusters section end to end.
#
# `BootstrapCluster` is stood in for on the mutating paths: it is exercised
# exhaustively in `spec/integration/cluster_bootstrap_spec.rb` and against a real
# Engine in `spec/integration/swarm_bootstrap_lab_spec.rb`, and what is under test
# here is the surface — routing, the tenancy boundary, what reaches the page and
# what a failure renders.
#
# The read paths run the **real** preflight, because that is what an operator
# gets. Assertions are on the shape of the report rather than on which checks
# pass, so this does not become a test of the machine it runs on.
RSpec.describe "clusters", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let!(:team) { create(:team, owner: owner, name: "Acme", slug: "acme") }

  before { https! }

  around do |example|
    config = Rails.application.env_config
    previous = config.values_at("action_dispatch.show_exceptions",
      "action_dispatch.show_detailed_exceptions")
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.show_detailed_exceptions"] = false

    example.run
  ensure
    config["action_dispatch.show_exceptions"] = previous[0]
    config["action_dispatch.show_detailed_exceptions"] = previous[1]
  end

  def sign_in_as(user)
    post sign_in_path, params: { email: user.email, password: password }
  end

  def member(role, of: team)
    user = create(:user, password: password)
    create(:team_member, team: of, user: user, role: role, status: "ACTIVE")
    user
  end

  def administrator(user)
    InstanceRole.create!(user: user, role: InstanceRole::ADMIN)
    user
  end

  describe "the list" do
    before { sign_in_as(owner) }

    it "shows the empty state before anything is bootstrapped" do
      get "/t/acme/clusters"

      expect(response).to have_http_status(:ok)
      expect(inertia_props["clusters"]).to be_empty
    end

    # AC11 reaches the page: the status, when it was observed and whether that
    # reading is stale all travel together, so no screen can present an old
    # reading as current.
    it "carries the observation and its age for each cluster" do
      create(:cluster, :bootstrapped, team: team, slug: "prod")

      get "/t/acme/clusters"

      cluster = inertia_props["clusters"].first
      expect(cluster["status"]).to eq("READY")
      expect(cluster["observedAt"]).to be_present
      expect(cluster["stale"]).to be(false)
      expect(cluster["operational"]).to be(true)
    end

    it "reports a stale reading as stale, and not as operational" do
      create(:cluster, :stale, team: team, slug: "prod")

      get "/t/acme/clusters"

      cluster = inertia_props["clusters"].first
      expect(cluster["stale"]).to be(true)
      expect(cluster["operational"]).to be(false)
    end

    # doc 06 §14.1: operational is not the same question as highly available, and
    # a single-node cluster is where the difference first bites.
    it "never claims high availability for a single-node cluster" do
      create(:cluster, :bootstrapped, team: team)

      get "/t/acme/clusters"

      expect(inertia_props["clusters"].first["highlyAvailable"]).to be(false)
    end

    # AC7 through the page: the cause is a named code, not a generic failure.
    it "carries the classified cause of an unreachable cluster" do
      create(:cluster, :unreachable, team: team)

      get "/t/acme/clusters"

      expect(inertia_props["clusters"].first["unreachableReason"]).to eq("DAEMON_UNREACHABLE")
    end

    it "shows only this Team's clusters" do
      create(:cluster, team: team, slug: "ours")
      create(:cluster, team: create(:team), slug: "theirs")

      get "/t/acme/clusters"

      expect(inertia_props["clusters"].map { |c| c["slug"] }).to eq([ "ours" ])
    end

    # AC9 reaching the interface: the UI does not offer what the server refuses.
    it "does not offer the bootstrap to somebody who is not an instance administrator" do
      get "/t/acme/clusters"

      expect(inertia_props["permissions"]).to eq({ "bootstrap" => false })
    end

    it "offers it to an OWNER who is one" do
      sign_in_as(administrator(create(:user, password: password)).tap do |user|
        create(:team_member, team: team, user: user, role: "ADMIN", status: "ACTIVE")
      end)

      get "/t/acme/clusters"

      expect(inertia_props["permissions"]).to eq({ "bootstrap" => true })
    end
  end

  # UC-003 steps 1 and 2: the checks and the detected addresses, before anything
  # is created.
  describe "the readiness checks" do
    before { sign_in_as(owner) }

    it "reports every check by name, with a status and a detail" do
      get "/t/acme/clusters/preflight"

      preflight = inertia_props["preflight"]
      names = preflight["checks"].map { |check| check["name"] }

      expect(names).to include("operating_system", "docker_daemon", "clock", "advertise_address")
      preflight["checks"].each do |check|
        expect(check["status"]).to be_in(%w[PASS FAIL UNKNOWN])
        expect(check["detail"]).to be_present
      end
    end

    it "changes nothing" do
      expect { get "/t/acme/clusters/preflight" }.not_to change(Cluster, :count)
    end

    # The browser is never told where the Engine is (doc 06 §4.2, AC8).
    it "puts no Engine address on the page" do
      get "/t/acme/clusters/preflight"

      expect(response.body).not_to include("2375")
      expect(response.body).not_to include("docker.sock")
      expect(response.body).not_to include("DOCKER_HOST")
    end
  end

  describe "bootstrapping" do
    let(:cluster) { build(:cluster, :bootstrapped, team: team) }

    before { sign_in_as(administrator(owner)) }

    it "creates the Cluster and returns to the list" do
      allow(BootstrapCluster).to receive(:call).and_return(
        Opanel::Result.success(cluster: create(:cluster, :bootstrapped, team: team))
      )

      post "/t/acme/clusters", params: { name: "Production", advertiseAddress: "10.0.0.5" }

      expect(response).to redirect_to("/t/acme/clusters")
    end

    it "passes the operator's advertise address through rather than guessing" do
      expect(BootstrapCluster).to receive(:call)
        .with(hash_including(advertise_address: "10.0.0.5", adopt_existing: false))
        .and_return(Opanel::Result.success(cluster: create(:cluster, team: team)))

      post "/t/acme/clusters", params: { name: "Production", advertiseAddress: "10.0.0.5" }
    end

    it "passes an explicit adoption through" do
      expect(BootstrapCluster).to receive(:call)
        .with(hash_including(adopt_existing: true))
        .and_return(Opanel::Result.success(cluster: create(:cluster, team: team)))

      post "/t/acme/clusters", params: { name: "Production", adoptExisting: "1" }
    end

    # AC4 through the page: the failing checks are named, so the operator knows
    # what to fix rather than that something is wrong.
    it "renders the failed checks when preflight blocks" do
      allow(BootstrapCluster).to receive(:call).and_return(
        Opanel::Result.failure(code: "PREFLIGHT_FAILED", message: BootstrapCluster::PREFLIGHT_BLOCKED,
          details: { failed_checks: [ { name: "clock", detail: "the system clock is not synchronized" } ] })
      )

      post "/t/acme/clusters", params: { name: "Production" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props["error"]["message"]).to eq(BootstrapCluster::PREFLIGHT_BLOCKED)
      expect(inertia_props["details"]["failedChecks"].first["name"]).to eq("clock")
    end

    # AC5 through the page: the candidates come back so the operator can choose.
    it "offers the candidate addresses when a choice is required" do
      allow(BootstrapCluster).to receive(:call).and_return(
        Opanel::Result.failure(code: "VALIDATION_ERROR", message: BootstrapCluster::ADVERTISE_REQUIRED,
          details: { candidates: %w[10.0.0.5 192.168.9.9] })
      )

      post "/t/acme/clusters", params: { name: "Production" }

      expect(inertia_props["details"]["candidates"]).to eq(%w[10.0.0.5 192.168.9.9])
    end

    it "renders an unreachable daemon with its classified cause, not a 500" do
      allow(BootstrapCluster).to receive(:call).and_return(
        Opanel::Result.failure(code: "ENGINE_UNAVAILABLE", message: "docker info failed",
          details: { cause: SwarmBootstrap::DAEMON_UNREACHABLE })
      )

      post "/t/acme/clusters", params: { name: "Production" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props["details"]["cause"]).to eq(SwarmBootstrap::DAEMON_UNREACHABLE)
    end

    # The controller forwards an allowlist, not the whole `details` hash — a
    # Command is free to put anything in there, and forwarding it wholesale turns
    # every future detail into a prop nobody reviewed.
    it "forwards only the failure details the page is meant to render" do
      allow(BootstrapCluster).to receive(:call).and_return(
        Opanel::Result.failure(code: "ENGINE_UNAVAILABLE", message: "failed",
          details: { cause: "X", internal_trace: "/app/executors/swarm_bootstrap.rb:42" })
      )

      post "/t/acme/clusters", params: { name: "Production" }

      expect(inertia_props["details"].keys).not_to include("internal_trace", "internalTrace")
      expect(response.body).not_to include("swarm_bootstrap.rb")
    end
  end

  # AC9: an actor without the instance role is refused by the Policy, and the
  # refusal is a page rather than a crash.
  describe "authorization (AC9)" do
    it "refuses an OWNER who is not an instance administrator" do
      sign_in_as(owner)

      post "/t/acme/clusters", params: { name: "Production" }

      expect(response).to have_http_status(:forbidden)
      expect(Cluster.count).to eq(0)
    end

    it "refuses a DEVELOPER who is an instance administrator" do
      sign_in_as(administrator(member("DEVELOPER")))

      post "/t/acme/clusters", params: { name: "Production" }

      expect(response).to have_http_status(:forbidden)
    end

    it "discloses nothing about why beyond the refusal" do
      sign_in_as(owner)

      post "/t/acme/clusters", params: { name: "Production" }

      expect(response.body).not_to include("instance_role_required")
      expect(response.body).not_to include("InstanceRole")
    end
  end

  describe "refreshing" do
    let!(:cluster) { create(:cluster, :stale, team: team) }

    it "takes a reading and returns to the list" do
      sign_in_as(member("VIEWER"))
      allow(RefreshClusterStatus).to receive(:call).and_return(Opanel::Result.success(cluster: cluster))

      post "/t/acme/clusters/#{cluster.external_id}/refresh"

      expect(response).to redirect_to("/t/acme/clusters")
    end

    it "answers a Cluster of another Team as absent" do
      sign_in_as(owner)
      theirs = create(:cluster, team: create(:team))

      post "/t/acme/clusters/#{theirs.external_id}/refresh"

      expect(response).to have_http_status(:not_found)
    end

    it "answers a malformed identifier identically" do
      sign_in_as(owner)

      post "/t/acme/clusters/not-an-id/refresh"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "cross-team" do
    let(:outsider) { administrator(create(:user, password: password)) }
    let!(:their_team) { create(:team, owner: outsider, slug: "beta") }
    let!(:cluster) { create(:cluster, :bootstrapped, team: team) }

    before { sign_in_as(outsider) }

    # An instance administrator is still not a member of somebody else's Team,
    # and the Swarm id of a running cluster is infrastructure they must not learn.
    it "answers 404 for another Team's cluster list, even to an instance administrator" do
      get "/t/acme/clusters"

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(cluster.swarm_id)
    end

    it "answers 404 when bootstrapping into another Team" do
      post "/t/acme/clusters", params: { name: "Theirs" }

      expect(response).to have_http_status(:not_found)
      expect(Cluster.where(name: "Theirs")).to be_empty
    end

    it "answers 404 when refreshing another Team's cluster through their own path" do
      post "/t/beta/clusters/#{cluster.external_id}/refresh"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "signed out" do
    it "does not reach the list" do
      get "/t/acme/clusters"

      expect(response).to redirect_to(sign_in_path)
    end

    it "does not bootstrap" do
      expect { post "/t/acme/clusters", params: { name: "Production" } }.not_to change(Cluster, :count)
    end
  end
end
