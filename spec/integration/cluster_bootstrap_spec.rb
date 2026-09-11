require "rails_helper"

# `BootstrapCluster` against real PostgreSQL, with the Engine stood in for.
#
# The Engine itself is exercised for real in `spec/integration/swarm_bootstrap_lab_spec.rb`
# against the disposable lab. What is tested here is everything a real daemon
# cannot be asked to do on demand: refuse, time out, be a worker, be too old, or
# already belong to somebody else's Swarm.
#
# The stand-in is a plain object with the same three methods, not a mock. A mock
# agrees with whatever the code believes, which is the belief under test.
RSpec.describe BootstrapCluster, :integration do
  let(:team) { create(:team) }
  let(:owner) { team.owner }

  # The ordinary actor: OWNER of the Team *and* INSTANCE_ADMIN, which is what
  # `BootstrapInstallation` produces for the person who sets the installation up.
  let(:administrator) do
    InstanceRole.create!(user: owner, role: InstanceRole::ADMIN)
    owner
  end

  def engine(**overrides)
    SwarmBootstrap::Info.new({
      engine_version: "29.7.2", swarm_state: "inactive", swarm_id: nil, node_id: "node1",
      manager?: false, node_count: 0, data_root: "/var/lib/docker"
    }.merge(overrides))
  end

  # Answers `info` with `before` until `init` is called, then with `after`.
  # Records what it was asked to advertise on.
  def fake_executor(before:, after: nil, init_error: nil)
    Class.new do
      class << self
        attr_accessor :before_info, :after_info, :init_error, :initialised, :advertised
      end
      self.before_info = before
      self.after_info = after
      self.init_error = init_error
      self.initialised = false

      def self.info(**)
        raise before_info if before_info.is_a?(StandardError)

        initialised ? after_info : before_info
      end

      def self.init(advertise_address:, **)
        raise init_error if init_error

        self.advertised = advertise_address
        self.initialised = true
        after_info.swarm_id
      end

      def self.redact(text) = SwarmBootstrap.redact(text)
    end
  end

  def preflight_for(executor, probe: nil)
    Preflight.call(probe: probe || permissive_probe, executor: executor)
  end

  # A machine where nothing blocks. The preflight itself is tested in
  # `spec/unit/preflight_spec.rb`; here it is a precondition, not the subject.
  def permissive_probe(interfaces: [ SystemProbe::Interface.new(name: "eth0", address: "10.0.0.5", loopback: false,
private: true) ])
    probe = Object.new
    probe.define_singleton_method(:operating_system) { "linux" }
    probe.define_singleton_method(:architecture) { "x86_64" }
    probe.define_singleton_method(:supported_platform?) { true }
    probe.define_singleton_method(:hostname) { "node-1" }
    probe.define_singleton_method(:hostname_resolves?) { true }
    probe.define_singleton_method(:clock_synchronized?) { true }
    probe.define_singleton_method(:free_disk_bytes) { |_| 200 * 1024**3 }
    probe.define_singleton_method(:free_inodes) { |_| 5_000_000 }
    probe.define_singleton_method(:path_on_this_host?) { |path| !path.nil? }
    probe.define_singleton_method(:port_free?) { |_port, protocol: :tcp| true }
    probe.define_singleton_method(:port_holder) { |_| nil }
    probe.define_singleton_method(:interfaces) { interfaces }
    probe
  end

  def bootstrap(actor: administrator, executor:, probe: nil, **arguments)
    described_class.call(
      actor: actor, team: team, name: arguments.fetch(:name, "Production"),
      slug: arguments[:slug], advertise_address: arguments[:advertise_address],
      adopt_existing: arguments.fetch(:adopt_existing, false),
      preflight: preflight_for(executor, probe: probe), executor: executor
    )
  end

  describe "an empty installation (AC1)" do
    let(:executor) do
      fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k", node_count: 1))
    end

    it "initialises a Swarm and registers the Cluster with its id" do
      result = bootstrap(executor: executor)

      expect(result).to be_success

      cluster = result.value.fetch(:cluster)
      expect(cluster.swarm_id).to eq("abcdefghij0123456789k")
      expect(cluster.team).to eq(team)
      expect(cluster.slug).to eq("production")
    end

    # AC11. The status is the observation just taken, and it carries its time.
    it "records the status as an observation, with when it was observed" do
      cluster = bootstrap(executor: executor).value.fetch(:cluster)

      expect(cluster.status).to eq(Cluster::READY)
      expect(cluster.observed_at).to be_within(5.seconds).of(Time.current)
      expect(cluster).not_to be_observation_stale
    end

    # A reading that could not verify everything is not a claim of health.
    it "records DEGRADED rather than READY when a check could not be evaluated" do
      probe = permissive_probe
      probe.define_singleton_method(:clock_synchronized?) { nil }

      cluster = bootstrap(executor: executor, probe: probe).value.fetch(:cluster)

      expect(cluster.status).to eq(Cluster::DEGRADED)
    end

    it "advertises on the address the machine offered" do
      bootstrap(executor: executor)

      expect(executor.advertised).to eq("10.0.0.5")
    end

    # AC9. The trail is what answers "who turned this machine into a cluster".
    it "records the bootstrap in the audit trail" do
      expect { bootstrap(executor: executor) }
        .to change { AuditLog.where(action: "cluster.bootstrapped").count }.by(1)

      record = AuditLog.where(action: "cluster.bootstrapped").last
      expect(record.team_id).to eq(team.id)
      expect(record.actor_id).to eq(administrator.id)
      expect(record.result).to eq("SUCCESS")
      expect(record.after).to include("swarm_id" => "abcdefghij0123456789k")
    end
  end

  # AC4. Nothing is created, and the Engine is never touched: a bootstrap that
  # starts and then discovers the clock is wrong has already made a Swarm
  # somebody has to tear down.
  describe "a machine that fails preflight (AC4)" do
    let(:executor) { fake_executor(before: engine, after: engine(swarm_state: "active")) }

    def blocked_probe(**overrides)
      probe = permissive_probe
      overrides.each { |name, value| probe.define_singleton_method(name) { |*| value } }
      probe
    end

    it "refuses on a clock that is not synchronized, naming the check" do
      result = bootstrap(executor: executor, probe: blocked_probe(clock_synchronized?: false))

      expect(result).to be_failure
      expect(result.code).to eq("PREFLIGHT_FAILED")
      expect(result.details[:failed_checks].map { |c| c[:name] }).to include("clock")
    end

    it "refuses on an occupied port" do
      result = bootstrap(executor: executor, probe: blocked_probe(port_free?: false))

      expect(result).to be_failure
      expect(result.details[:failed_checks].map { |c| c[:name] }).to include("port_2377_tcp")
    end

    it "refuses on an Engine below the minimum, naming both versions" do
      old = fake_executor(before: engine(engine_version: "20.10.0"), after: engine)
      result = bootstrap(executor: old)

      expect(result).to be_failure
      detail = result.details[:failed_checks].find { |c| c[:name] == "engine_version" }[:detail]
      expect(detail).to include("20.10.0", Preflight::MINIMUM_ENGINE_VERSION)
    end

    it "creates nothing and never touches the Engine" do
      expect {
        bootstrap(executor: executor, probe: blocked_probe(clock_synchronized?: false))
      }.not_to change(Cluster, :count)

      expect(executor.initialised).to be(false)
    end
  end

  # A machine whose interfaces could not be listed answers `nil`, which is not the
  # same as having none. Calling `.map` on it raised `NoMethodError` — a refusal
  # turning into a crash. Review found it.
  describe "when the machine's interfaces cannot be listed" do
    let(:executor) do
      fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k"))
    end

    it "refuses with a typed failure rather than crashing" do
      result = bootstrap(executor: executor, probe: permissive_probe(interfaces: nil),
        advertise_address: "10.0.0.5")

      expect(result).to be_failure
      expect(result.code).to eq("VALIDATION_ERROR")
      expect(result.message).to eq(described_class::ADVERTISE_UNKNOWN)
    end
  end

  # AC5. Never guessed: the address other nodes will use is the operator's
  # decision, and a wrong one produces a Swarm nobody can join.
  describe "several network interfaces (AC5)" do
    let(:executor) do
      fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k"))
    end

    let(:two_interfaces) do
      [ SystemProbe::Interface.new(name: "eth0", address: "10.0.0.5", loopback: false, private: true),
        SystemProbe::Interface.new(name: "eth1", address: "192.168.9.9", loopback: false, private: true) ]
    end

    it "refuses to choose, and offers the candidates" do
      result = bootstrap(executor: executor, probe: permissive_probe(interfaces: two_interfaces))

      expect(result).to be_failure
      expect(result.message).to eq(described_class::ADVERTISE_REQUIRED)
      expect(result.details[:candidates]).to match_array(%w[10.0.0.5 192.168.9.9])
      expect(executor.initialised).to be(false)
    end

    it "accepts the address the operator chose" do
      result = bootstrap(executor: executor, probe: permissive_probe(interfaces: two_interfaces),
        advertise_address: "192.168.9.9")

      expect(result).to be_success
      expect(executor.advertised).to eq("192.168.9.9")
      expect(result.value.fetch(:cluster).advertise_address).to eq("192.168.9.9")
    end

    # A typo that is accepted silently becomes a Swarm no other node can reach.
    it "refuses an address this machine does not have" do
      result = bootstrap(executor: executor, probe: permissive_probe(interfaces: two_interfaces),
        advertise_address: "203.0.113.7")

      expect(result).to be_failure
      expect(result.message).to eq(described_class::ADVERTISE_UNKNOWN)
      expect(executor.initialised).to be(false)
    end
  end

  # AC6. Detected always; adopted only when compatible and asked for.
  describe "a Swarm that already exists (AC6)" do
    let(:existing) do
      engine(swarm_state: "active", manager?: true, swarm_id: "existingswarm0123456", node_count: 1)
    end
    let(:executor) { fake_executor(before: existing, after: existing) }

    it "detects it and refuses to register it without an explicit adoption" do
      result = bootstrap(executor: executor)

      expect(result).to be_failure
      expect(result.code).to eq("CONFLICT")
      expect(result.message).to include("existingswarm0123456")
      expect(result.details[:adoptable]).to be(true)
      expect(Cluster.count).to eq(0)
    end

    it "adopts it when asked, without initialising anything" do
      result = bootstrap(executor: executor, adopt_existing: true)

      expect(result).to be_success
      expect(result.value.fetch(:cluster).swarm_id).to eq("existingswarm0123456")
      expect(executor.initialised).to be(false)
    end

    it "records the adoption as its own action, not as a bootstrap" do
      expect { bootstrap(executor: executor, adopt_existing: true) }
        .to change { AuditLog.where(action: "cluster.adopted").count }.by(1)
        .and change { AuditLog.where(action: "cluster.bootstrapped").count }.by(0)
    end

    # A worker cannot host a control plane, and adopting one would produce a
    # Cluster that can never accept an operation.
    it "refuses to adopt a Swarm this node joined as a worker" do
      worker = fake_executor(before: existing.dup.tap { |i| i[:manager?] = false }, after: existing)
      result = bootstrap(executor: worker, adopt_existing: true)

      expect(result).to be_failure
      expect(result.message).to eq(described_class::NOT_A_MANAGER)
    end

    # Two Cluster rows converging on one Swarm is a split brain in the Control
    # Plane. The partial unique index refuses it too; this turns that into a
    # sentence.
    it "refuses to adopt a Swarm another Cluster already claims" do
      create(:cluster, team: create(:team), swarm_id: "existingswarm0123456", status: "READY",
        observed_at: Time.current)

      result = bootstrap(executor: executor, adopt_existing: true)

      expect(result).to be_failure
      expect(result.message).to eq(described_class::ALREADY_REGISTERED)
    end
  end

  # AC7. Classified, never a generic timeout, and nothing is registered — there
  # is no Swarm to register.
  describe "a daemon that does not answer (AC7)" do
    it "reports the classified cause and creates nothing" do
      down = fake_executor(before: SwarmBootstrap::EngineError.new(
        SwarmBootstrap::DAEMON_UNREACHABLE, "docker info failed: Cannot connect to the Docker daemon"
      ))

      expect { @result = bootstrap(executor: down) }.not_to change(Cluster, :count)

      expect(@result).to be_failure
      expect(@result.details[:failed_checks].map { |c| c[:name] }).to include("docker_daemon")
    end

    it "distinguishes a slow daemon from an absent one" do
      slow = fake_executor(before: SwarmBootstrap::EngineError.new(
        SwarmBootstrap::DAEMON_TIMEOUT, "docker info failed: timed out after 20s"
      ))

      detail = bootstrap(executor: slow).details[:failed_checks]
        .find { |c| c[:name] == "docker_daemon" }[:detail]

      expect(detail).to include(SwarmBootstrap::DAEMON_TIMEOUT)
      expect(detail).not_to include(SwarmBootstrap::DAEMON_UNREACHABLE)
    end

    # An authorized actor tried to turn a machine into a cluster node and it
    # failed. doc 04 §10 wants the privileged action recorded with its result: a
    # trail holding only the successes cannot answer "who has been trying this".
    # The action was declared and never emitted until review pointed it out.
    it "records the failed attempt in the audit trail, with the classified cause" do
      down = fake_executor(before: SwarmBootstrap::EngineError.new(
        SwarmBootstrap::DAEMON_UNREACHABLE, "docker info failed: Cannot connect to the Docker daemon"
      ))

      expect { bootstrap(executor: down) }
        .to change { AuditLog.where(action: "cluster.bootstrap_failed").count }.by(1)

      record = AuditLog.where(action: "cluster.bootstrap_failed").last
      expect(record.result).to eq("FAILED")
      expect(record.team_id).to eq(team.id)
      expect(record.actor_id).to eq(administrator.id)
      # A daemon that will not answer fails the preflight, so the recorded reason
      # is the check that failed rather than the Engine's cause code. Both paths
      # audit; they name what stopped the attempt in their own vocabulary.
      expect(record.after).to eq({ "unreachable_reason" => "docker_daemon" })
    end

    # The Engine's own message can carry a path or a token; only the classified
    # vocabulary is recorded.
    it "records the cause code and not the daemon's own message" do
      down = fake_executor(before: SwarmBootstrap::EngineError.new(
        SwarmBootstrap::DAEMON_UNREACHABLE, "docker info failed: /var/run/docker.sock is missing"
      ))

      bootstrap(executor: down)

      expect(AuditLog.where(action: "cluster.bootstrap_failed").last.attributes.to_s)
        .not_to include("docker.sock")
    end

    # A refusal *before* authorization is not an attempt worth auditing as one —
    # `authorization.denied` already records it, and recording both would double
    # count every probe.
    it "does not record a bootstrap attempt for somebody who was never authorized" do
      down = fake_executor(before: SwarmBootstrap::EngineError.new(
        SwarmBootstrap::DAEMON_UNREACHABLE, "cannot connect"
      ))

      expect { bootstrap(actor: owner, executor: down) }
        .not_to change { AuditLog.where(action: "cluster.bootstrap_failed").count }
    end

    it "records the Engine's cause code when the failure happens during the init" do
      failing = fake_executor(
        before: engine,
        after: engine(swarm_state: "active"),
        init_error: SwarmBootstrap::EngineError.new(SwarmBootstrap::SWARM_INIT_REFUSED, "refused")
      )

      bootstrap(executor: failing)

      expect(AuditLog.where(action: "cluster.bootstrap_failed").last.after)
        .to eq({ "unreachable_reason" => SwarmBootstrap::SWARM_INIT_REFUSED })
    end

    it "reports a failure during the init itself with its cause" do
      failing = fake_executor(
        before: engine,
        after: engine(swarm_state: "active"),
        init_error: SwarmBootstrap::EngineError.new(SwarmBootstrap::SWARM_INIT_REFUSED,
          "docker swarm init failed: could not choose an IP address")
      )

      result = bootstrap(executor: failing)

      expect(result).to be_failure
      expect(result.code).to eq("ENGINE_UNAVAILABLE")
      expect(result.details[:cause]).to eq(SwarmBootstrap::SWARM_INIT_REFUSED)
      expect(Cluster.count).to eq(0)
    end
  end

  # AC10. The token is the credential that lets anybody join the cluster. It must
  # not survive anywhere — and the planted value is a real one's shape, so this
  # fails if the scrubbing is removed.
  describe "the Swarm join token (AC10)" do
    # `SWMTKN-`-shaped and obviously fake: the redaction matches the prefix, so
    # the shape is what the test needs. See the note in
    # `spec/security/docker_api_exposure_spec.rb`.
    let(:token) { "SWMTKN-1-example-not-a-real-token-do-not-use-x1" }

    it "never appears in the failure returned to the caller" do
      leaking = fake_executor(
        before: engine,
        after: engine(swarm_state: "active"),
        init_error: SwarmBootstrap::EngineError.new(SwarmBootstrap::SWARM_INIT_REFUSED,
          "docker swarm init failed: to add a worker run docker swarm join --token #{token}")
      )

      result = bootstrap(executor: leaking)

      expect(result.message).not_to include(token)
      expect(result.message).not_to include("SWMTKN")
      expect(result.message).to include(SwarmBootstrap::REDACTED)
    end

    it "never appears in the application log" do
      leaking = fake_executor(
        before: engine,
        after: engine(swarm_state: "active"),
        init_error: SwarmBootstrap::EngineError.new(SwarmBootstrap::SWARM_INIT_REFUSED,
          "docker swarm init failed: docker swarm join --token #{token}")
      )

      output = capture_log { bootstrap(executor: leaking) }

      expect(output).not_to include("SWMTKN")
    end

    it "never appears in the audit trail" do
      executor = fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k"))

      bootstrap(executor: executor)

      expect(AuditLog.all.map { |record| record.attributes.to_s }.join).not_to include("SWMTKN")
    end

    # The control. Without it the three examples above pass on a system that
    # never had a token to leak, which is the shape of a check that cannot fail.
    it "would be caught: the redaction is what removes it" do
      raw = "docker swarm join --token #{token} 10.0.0.5:2377"

      expect(raw).to include("SWMTKN")
      expect(SwarmBootstrap.redact(raw)).not_to include("SWMTKN")
    end
  end

  # AC9, from the Command's side. The Policy is tested exhaustively in
  # `spec/policies/cluster_policy_spec.rb`; what matters here is that the Command
  # goes through it.
  describe "authorization (AC9)" do
    let(:executor) do
      fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k"))
    end

    it "refuses an OWNER who is not an instance administrator" do
      result = bootstrap(actor: owner, executor: executor)

      expect(result).to be_failure
      expect(result.code).to eq("FORBIDDEN")
      expect(Cluster.count).to eq(0)
      expect(executor.initialised).to be(false)
    end

    # The refusal does not say *which* of the two conditions failed. Telling an
    # actor whether they lack the Team role or the instance grant is an oracle
    # about the installation.
    it "does not disclose which condition failed" do
      result = bootstrap(actor: owner, executor: executor)

      expect(result.message).not_to include("INSTANCE_ADMIN")
      expect(result.message).not_to include("instance")
    end

    it "records the denial in the audit trail with the classified reason" do
      expect { bootstrap(actor: owner, executor: executor) }
        .to change { AuditLog.where(action: "authorization.denied").count }.by(1)

      expect(AuditLog.where(action: "authorization.denied").last.after)
        .to eq({ "reason" => "instance_role_required" })
    end

    it "names the missing instance role as the reason, not a scope problem" do
      decision = ClusterPolicy.new(owner, Cluster.new(team: team)).decide(:bootstrap)

      expect(decision.reason).to eq(:instance_role_required)
    end

    # NOT_FOUND, not FORBIDDEN: an actor outside the Team must not learn that it
    # exists (Annex C §7.3), and an instance administrator is still outside it.
    it "answers an instance administrator with no membership as if the Team were absent" do
      outsider = create(:user)
      InstanceRole.create!(user: outsider, role: InstanceRole::ADMIN)

      result = bootstrap(actor: outsider, executor: executor)

      expect(result).to be_failure
      expect(result.code).to eq("NOT_FOUND")
      expect(result.message).not_to include(team.name)
    end
  end

  describe "naming" do
    let(:executor) do
      fake_executor(before: engine, after: engine(swarm_state: "active", manager?: true,
        swarm_id: "abcdefghij0123456789k"))
    end

    it "refuses a second cluster with the same slug in the same Team" do
      create(:cluster, team: team, slug: "production")

      result = bootstrap(executor: executor, name: "Production")

      expect(result).to be_failure
      expect(result.message).to eq(described_class::SLUG_TAKEN)
    end

    it "allows the same slug in a different Team" do
      create(:cluster, team: create(:team), slug: "production")

      expect(bootstrap(executor: executor, name: "Production")).to be_success
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
