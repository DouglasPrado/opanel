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

  # AC1 — the branch that runs `SwarmBootstrap.init` against a real Engine.
  #
  # ## It is not covered here, and this says so rather than pretending
  #
  # Initialising needs a daemon that is **not** already in a Swarm, and the only
  # way to produce one from here is to take this daemon out of its own. That is a
  # destructive operation on the developer's machine, and the workspace guardrail
  # denies it — correctly, and by design: `AGENT_RULES` puts destructive Docker
  # operations behind an explicit human gate, and an agent may not route around a
  # hook that enforces one.
  #
  # An earlier version of this file tried anyway, with the teardown in an `around`
  # hook. It did not work, and **it did not fail either**: RSpec runs `before`
  # hooks inside an `around`, so the global `:swarm` guard saw a daemon that had
  # just left its Swarm, could not read the lab label off a node that no longer
  # existed, and skipped. Both examples reported as pending for a reason that had
  # nothing to do with the opt-in they documented, and the Story report claimed
  # the path was "proved on demand" while nothing had ever invoked it. The
  # independent review caught that by running the opt-in and watching the skip.
  #
  # ## What does cover the branch, and what does not
  #
  # `spec/integration/cluster_bootstrap_spec.rb` exercises every decision around
  # the call — that it is reached only on an inactive daemon, with the operator's
  # chosen address, that the Swarm id is read back rather than parsed out of the
  # output, and that a failure during it is classified — against a stand-in
  # Engine. What is **not** proved is that a real `docker swarm init` accepts
  # those arguments and answers as expected.
  #
  # Closing that needs one human command, and then this suite has an inactive
  # daemon to work with:
  #
  #     bin/swarm-lab down && bundle exec rspec spec/integration/swarm_bootstrap_lab_spec.rb
  #     bin/swarm-lab up
  #
  # The example below runs when it finds one, and is skipped — never reported as
  # passing (Annex D §7) — when it does not.
  # `swarm: false` un-tags this block, and that is the whole trick.
  #
  # The global `:swarm` guard identifies the lab by a **node label**, and a node
  # label needs a node, and a node needs a Swarm. A daemon that has left its Swarm
  # therefore cannot be recognised as the lab — so under that tag these two
  # examples skip for a reason that has nothing to do with them, which is exactly
  # what the independent review caught. Their precondition is the absence of a
  # Swarm; they cannot live under a guard that requires one.
  #
  # What replaces it is the same guarantee by the other route the lab itself uses:
  # the **endpoint** must be a local socket, which `SwarmBootstrap` now refuses
  # anything else. A daemon that is inactive, local, and that this repository was
  # asked to initialise is as identified as an un-swarmed daemon can be.
  describe "initialising an inactive daemon (AC1)", swarm: false do
    let(:label) { Opanel::Gates::SwarmLab.label(Rails.root.to_s) }

    before do
      skip "the Docker daemon is not reachable — run `bin/swarm-lab up`." unless SwarmBootstrap.reachable?

      if SwarmBootstrap.info.swarm_active?
        skip "this daemon is already in a Swarm, and taking it out is a destructive operation " \
             "this suite may not perform. Run `bin/swarm-lab down` first to cover this branch, " \
             "then `bin/swarm-lab up` to restore the lab."
      end
    end

    # One initialisation, and everything a real one has to be true about.
    #
    # Split in two, the second example could never run: the first takes the
    # daemon it needed. Each `bin/swarm-lab down` buys exactly one initialisation,
    # so both assertions are made about the same one — which is also honest, since
    # they *are* two facts about a single `docker swarm init`.
    it "turns an inactive daemon into a Swarm, registers its id, and leaks no join token" do
      expect(SwarmBootstrap.info).to be_swarm_inactive

      output = capture_log { @result = bootstrap(advertise_address: LAB_ADVERTISE_ADDRESS) }

      # Label first: an assertion failure after this point must not leave the lab
      # unidentifiable, which `assert_claimable!` would then refuse to reclaim.
      if @result.success?
        node = Opanel::Gates::SwarmLab.docker!("node", "inspect", "self", "--format", "{{.ID}}")
        Opanel::Gates::SwarmLab.docker!("node", "update", "--label-add", "#{label}=true", node)
      end

      expect(@result).to be_success

      cluster = @result.value.fetch(:cluster)
      expect(cluster.swarm_id).to match(Cluster::SWARM_ID_FORMAT)
      expect(cluster.swarm_id).to eq(SwarmBootstrap.info.swarm_id)
      expect(cluster.advertise_address).to eq(LAB_ADVERTISE_ADDRESS)
      expect(cluster.observed_at).to be_present
      expect(SwarmBootstrap.info).to be_swarm_active

      # AC10 against a real initialisation, which really does print a join token
      # in its success message.
      expect(output).not_to include("SWMTKN")
      expect(AuditLog.all.map { |record| record.attributes.to_s }.join).not_to include("SWMTKN")

      # The control: the daemon really does hold a token, so the absence above is
      # the redaction working rather than a Swarm that has none.
      expect(Opanel::Gates::SwarmLab.docker!("swarm", "join-token", "-q", "worker"))
        .to start_with("SWMTKN")
    end
  end

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
