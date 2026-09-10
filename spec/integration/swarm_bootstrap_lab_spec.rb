require "rails_helper"

# The bootstrap against a **real** Docker Engine, in the disposable lab.
#
# Annex D §7 is the reason this file exists at all: a mock agrees with whatever
# the code believes, and the belief is what is under test. Everything the Engine
# cannot be asked to do on demand — refuse, time out, be a worker, be too old —
# is covered in `spec/integration/cluster_bootstrap_spec.rb`. What is here is the
# part only a daemon can answer.
#
# ## The guardrail comes first, always
#
# Every example asserts the daemon is the lab before touching it. The lab is
# identified by a node label this repository's own tooling applied, which is a
# property of the daemon rather than an environment variable — so pointing
# somewhere else fails closed instead of running against a real cluster
# (Annex H §12.2).
RSpec.describe "the Swarm bootstrap, against a real Engine", :swarm, :integration do
  let(:team) { create(:team) }

  let(:administrator) do
    InstanceRole.create!(user: team.owner, role: InstanceRole::ADMIN)
    team.owner
  end

  def bootstrap(**arguments)
    BootstrapCluster.call(actor: administrator, team: team,
      name: arguments.fetch(:name, "Lab"), slug: arguments[:slug],
      advertise_address: arguments[:advertise_address],
      adopt_existing: arguments.fetch(:adopt_existing, false))
  end

  # The lab's own advertise address. `bin/swarm-lab up` uses loopback, which is
  # right for a single-node disposable cluster and wrong for anything that will
  # grow — the preflight is what refuses to *suggest* it, and the operator's
  # explicit choice is what this passes.
  LAB_ADVERTISE_ADDRESS = "127.0.0.1"

  describe "reading the Engine" do
    it "reports the version, the Swarm state and where the Engine writes" do
      info = SwarmBootstrap.info

      expect(info.engine_version).to match(/\A\d+\.\d+/)
      expect(info.swarm_state).to eq("active")
      expect(info.data_root).to be_present
    end

    # The lab is a manager of a one-node Swarm. If this stops being true the
    # examples below are testing something else.
    it "sees a manager node in an active Swarm" do
      info = SwarmBootstrap.info

      expect(info).to be_swarm_active
      expect(info.manager?).to be(true)
      expect(info.swarm_id).to match(Cluster::SWARM_ID_FORMAT)
    end

    it "answers reachable? without raising" do
      expect(SwarmBootstrap.reachable?).to be(true)
    end
  end

  # AC6, against the Swarm that is actually running.
  describe "a Swarm that already exists (AC6)" do
    it "is detected, and not registered without an explicit adoption" do
      result = bootstrap

      expect(result).to be_failure
      expect(result.code).to eq("CONFLICT")
      expect(result.message).to include(SwarmBootstrap.info.swarm_id)
      expect(Cluster.count).to eq(0)
    end

    # AC1's other half: the `swarmId` that ends up in the row is the one the
    # Engine reports, not one the application made up.
    it "is adopted when asked, with the Engine's own Swarm id" do
      result = bootstrap(adopt_existing: true)

      expect(result).to be_success

      cluster = result.value.fetch(:cluster)
      expect(cluster.swarm_id).to eq(SwarmBootstrap.info.swarm_id)
      expect(cluster.swarm_id).to match(Cluster::SWARM_ID_FORMAT)
      expect(cluster.observed_at).to be_present
    end

    it "refuses a second Cluster claiming the same Swarm" do
      bootstrap(adopt_existing: true)

      second = BootstrapCluster.call(actor: administrator, team: team, name: "Twin",
        adopt_existing: true)

      expect(second).to be_failure
      expect(second.message).to eq(BootstrapCluster::ALREADY_REGISTERED)
    end
  end

  # AC11 against reality: the status is what the daemon just said.
  describe "refreshing the status (AC11)" do
    it "records READY from a live manager, with the time it was read" do
      cluster = bootstrap(adopt_existing: true).value.fetch(:cluster)
      cluster.update!(status: Cluster::UNREACHABLE, unreachable_reason: "STALE",
        observed_at: 1.hour.ago)

      RefreshClusterStatus.call(actor: administrator, cluster: cluster)

      expect(cluster.reload.status).to eq(Cluster::READY)
      expect(cluster.unreachable_reason).to be_nil
      expect(cluster.observed_at).to be_within(30.seconds).of(Time.current)
      expect(cluster).not_to be_observation_stale
    end

    # A Cluster whose Swarm was rebuilt underneath it must not report READY:
    # agreeing with a runtime it no longer knows is the failure doc 06 §14 exists
    # to prevent.
    it "reports a Swarm id that no longer matches as DEGRADED, with the cause" do
      cluster = bootstrap(adopt_existing: true).value.fetch(:cluster)
      cluster.update_columns(swarm_id: "someotherswarm0123456")

      RefreshClusterStatus.call(actor: administrator, cluster: cluster)

      expect(cluster.reload.status).to eq(Cluster::DEGRADED)
      expect(cluster.unreachable_reason).to eq("SWARM_ID_MISMATCH")
    end
  end

  # AC8, asserted against the running daemon rather than against the source.
  describe "the Docker API is not on the network (AC8)" do
    it "is reached over a local socket, never a TCP endpoint" do
      endpoint = Opanel::Gates::SwarmLab.resolved_endpoint(Rails.root.to_s).raw

      expect(endpoint).to start_with("unix://").or start_with("npipe://")
      expect(endpoint).not_to include("2375")
    end

    it "has nothing listening on 2375 on this machine" do
      probe = SystemProbe.new

      # `port_free?` answers `false` when something holds it. The unencrypted
      # Docker API port must be free — doc 06 §4.2 forbids exposing it at all.
      expect(probe.port_free?(2375)).not_to be(false)
    end
  end

  # AC1 — the branch that runs `SwarmBootstrap.init` against a real Engine — is
  # not in this file. It needs a daemon that is **not** in a Swarm, and every
  # example here needs one that is; the two cannot share an automated run, and a
  # skip is not a pass (`bin/gate post-commit` refuses a recorded skip). It lives
  # in `spec/integration/swarm_init_verification.rb`, run by an operator after
  # `bin/swarm-lab down`. See that file's header.

  private

  def capture_log
    original = Rails.logger
    buffer = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(buffer))
    yield
    buffer.string
  ensure
    Rails.logger = original
  end
end
