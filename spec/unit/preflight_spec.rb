require "rails_helper"
require "yaml"

# The preflight checks of doc 06 §3.2 (AC3), and the three conditions AC4 says
# must **block** a bootstrap: a skewed clock, an occupied port and an
# incompatible Engine.
#
# ## Why the probe is a collaborator
#
# Every one of those is a FAIL branch, and none of them can be reached on a
# machine whose clock is fine and whose ports are free. Without a probe to stand
# in for the operating system, the only examples possible here would be the ones
# that pass today — which is a suite that agrees with the machine it runs on
# rather than one that tests the code.
#
# The stand-ins below are plain objects, not mocks: they answer the same
# questions the real probe answers, and a change to that contract breaks them
# rather than being silently absorbed.
RSpec.describe Preflight, type: :unit do
  # A machine where everything is fine. Each example changes exactly the one
  # thing it is about, so a failure names its own cause.
  class HealthyProbe
    Interface = SystemProbe::Interface

    def initialize(**overrides) = @overrides = overrides

    def operating_system = fetch(:operating_system, "linux")
    def architecture = fetch(:architecture, "x86_64")
    def supported_platform? = fetch(:supported_platform, true)
    def hostname = fetch(:hostname, "node-1.internal")
    def hostname_resolves? = fetch(:hostname_resolves, true)
    def clock_synchronized? = fetch(:clock_synchronized, true)
    def free_disk_bytes(_path) = fetch(:free_disk_bytes, 200 * 1024 * 1024 * 1024)
    def free_inodes(_path) = fetch(:free_inodes, 5_000_000)
    def path_on_this_host?(path) = fetch(:path_on_this_host, !path.nil?)
    def port_free?(port, protocol: :tcp) = fetch(:port_free, {}).fetch([ port, protocol ], true)
    def port_holder(_port) = fetch(:port_holder, nil)

    def interfaces
      fetch(:interfaces, [ Interface.new(name: "eth0", address: "10.0.0.5", loopback: false, private: true) ])
    end

    private

    def fetch(key, default) = @overrides.fetch(key, default)
  end

  # An Engine that answers. `data_root` is a path the probe will call local, so
  # the host-measuring checks actually run.
  def engine(**overrides)
    SwarmBootstrap::Info.new({
      engine_version: "29.7.2", swarm_state: "inactive", swarm_id: nil, node_id: nil,
      manager?: false, node_count: 0, data_root: "/var/lib/docker"
    }.merge(overrides))
  end

  # A stand-in for the executor. Returns the Info it was built with, or raises
  # the EngineError it was built with.
  def executor_for(answer)
    Class.new do
      define_singleton_method(:answer) { answer }
      def self.info(**) = answer.is_a?(StandardError) ? raise(answer) : answer
    end
  end

  def run(probe: HealthyProbe.new, engine_info: engine)
    described_class.call(probe: probe, executor: executor_for(engine_info))
  end

  def check(result, name) = result.checks.find { |entry| entry.name == name }

  describe "the report" do
    # AC3: every check reports on its own. A single boolean would say something is
    # wrong and nothing about what.
    it "answers every check of doc 06 §3.2 individually" do
      names = run.checks.map(&:name)

      expect(names).to include("operating_system", "hostname", "docker_daemon", "engine_version",
        "clock", "disk_space", "inodes", "advertise_address")
      expect(names).to include("port_2377_tcp", "port_7946_tcp", "port_7946_udp", "port_4789_udp")
    end

    it "passes on a healthy machine, and blocks nothing" do
      result = run

      expect(result.failures).to be_empty
      expect(result).not_to be_blocked
    end

    # The number the platform is developed against lives in
    # `config/architecture/docker-lab.yml`. Declaring it again in the application
    # would be fine only if the two could not drift; this is what makes that true.
    it "requires the same minimum Engine version the lab configuration records" do
      recorded = YAML.safe_load_file(Rails.root.join("config/architecture/docker-lab.yml"))
        .dig("engine", "minimum_version")

      expect(described_class::MINIMUM_ENGINE_VERSION).to eq(recorded)
    end
  end

  describe "what blocks the bootstrap (AC4)" do
    it "blocks on a clock that is not synchronized, and says why it matters" do
      result = run(probe: HealthyProbe.new(clock_synchronized: false))

      expect(check(result, "clock")).to be_fail
      expect(check(result, "clock").detail).to match(/TLS|consensus/i)
      expect(result).to be_blocked
    end

    it "blocks on an occupied port, naming the port and what needs it" do
      result = run(probe: HealthyProbe.new(port_free: { [ 2377, :tcp ] => false }))

      expect(check(result, "port_2377_tcp")).to be_fail
      expect(check(result, "port_2377_tcp").detail).to include("2377/tcp")
      expect(check(result, "port_2377_tcp").detail).to include("Swarm control plane")
      expect(result).to be_blocked
    end

    it "names the process holding the port when the machine will say" do
      result = run(probe: HealthyProbe.new(port_free: { [ 2377, :tcp ] => false },
        port_holder: "dockerd (pid 42)"))

      expect(check(result, "port_2377_tcp").detail).to include("dockerd (pid 42)")
    end

    it "blocks on an Engine below the supported minimum, naming both versions" do
      result = run(engine_info: engine(engine_version: "23.0.1"))

      expect(check(result, "engine_version")).to be_fail
      expect(check(result, "engine_version").detail).to include("23.0.1")
      expect(check(result, "engine_version").detail).to include(described_class::MINIMUM_ENGINE_VERSION)
      expect(result).to be_blocked
    end

    it "accepts an Engine exactly at the minimum" do
      result = run(engine_info: engine(engine_version: described_class::MINIMUM_ENGINE_VERSION))

      expect(check(result, "engine_version")).to be_pass
    end

    it "blocks on an unsupported platform" do
      result = run(probe: HealthyProbe.new(supported_platform: false, operating_system: "aix"))

      expect(check(result, "operating_system")).to be_fail
      expect(result).to be_blocked
    end

    it "blocks on a hostname the machine cannot resolve" do
      result = run(probe: HealthyProbe.new(hostname_resolves: false))

      expect(check(result, "hostname")).to be_fail
      expect(result).to be_blocked
    end

    it "blocks on too little disk, naming the filesystem" do
      result = run(probe: HealthyProbe.new(free_disk_bytes: 1024))

      expect(check(result, "disk_space")).to be_fail
      expect(check(result, "disk_space").detail).to include("/var/lib/docker")
      expect(result).to be_blocked
    end

    it "blocks on too few inodes" do
      result = run(probe: HealthyProbe.new(free_inodes: 10))

      expect(check(result, "inodes")).to be_fail
    end

    it "blocks when no address another node could reach exists" do
      loopback = SystemProbe::Interface.new(name: "lo", address: "127.0.0.1", loopback: true, private: false)
      result = run(probe: HealthyProbe.new(interfaces: [ loopback ]))

      expect(check(result, "advertise_address")).to be_fail
      expect(result).to be_blocked
    end
  end

  # The third outcome, and the one that keeps the other two honest. doc 06 §3.1
  # says the installer aborts on conditions it cannot verify; reporting UNKNOWN
  # is how that reaches the operator instead of being decided here.
  describe "what it refuses to guess" do
    it "reports an undeterminable clock as unknown rather than as failing" do
      result = run(probe: HealthyProbe.new(clock_synchronized: nil))

      expect(check(result, "clock")).to be_unknown
      expect(result).not_to be_blocked
    end

    # This is not hypothetical. `systemsetup -getusingnetworktime` exits 0 while
    # refusing without root, and reading that as "not synchronized" blocked the
    # bootstrap on a perfectly healthy machine — found by running the real probe
    # against the machine this was written on.
    it "does not turn 'I cannot tell' into 'the clock is wrong'" do
      expect(check(run(probe: HealthyProbe.new(clock_synchronized: nil)), "clock")).not_to be_fail
    end

    it "reports an unmeasurable filesystem as unknown rather than as enough" do
      result = run(probe: HealthyProbe.new(free_disk_bytes: nil))

      expect(check(result, "disk_space")).to be_unknown
      expect(check(result, "disk_space")).not_to be_pass
    end

    it "reports interfaces it could not enumerate as unknown, not as none" do
      result = run(probe: HealthyProbe.new(interfaces: nil))

      expect(check(result, "advertise_address")).to be_unknown
      expect(result).not_to be_blocked
    end

    # An Engine in a VM is a legitimate development setup, and the host's ports,
    # disk and interfaces then say nothing about where the Swarm will run. This is
    # the check that stops four others from reporting PASS about the wrong
    # machine — which the real probe did, on a host that reported 2377/tcp free
    # while the Swarm was active and listening on it inside the VM.
    context "when the Engine does not run on this host" do
      let(:result) { run(probe: HealthyProbe.new(path_on_this_host: false)) }

      it "says so, without failing" do
        expect(check(result, "engine_locality")).to be_unknown
        expect(result).not_to be_blocked
      end

      it "refuses to report the host's ports as the Swarm's" do
        expect(check(result, "port_2377_tcp")).to be_unknown
        expect(check(result, "port_4789_udp")).to be_unknown
      end

      it "refuses to measure the host's disk as the Engine's" do
        expect(check(result, "disk_space")).to be_unknown
        expect(check(result, "inodes")).to be_unknown
      end

      it "refuses to offer the host's addresses as advertise candidates" do
        expect(check(result, "advertise_address")).to be_unknown
      end
    end
  end

  # AC7: the daemon's absence arrives as a named cause, never as a generic
  # timeout, and every Docker-dependent check reports that it could not run.
  describe "when the daemon does not answer" do
    let(:result) do
      run(engine_info: SwarmBootstrap::EngineError.new(SwarmBootstrap::DAEMON_UNREACHABLE,
        "docker info failed: Cannot connect to the Docker daemon"))
    end

    it "fails the daemon check with the classified cause" do
      expect(check(result, "docker_daemon")).to be_fail
      expect(check(result, "docker_daemon").detail).to include(SwarmBootstrap::DAEMON_UNREACHABLE)
      expect(result).to be_blocked
    end

    it "does not claim to know the Engine version" do
      expect(check(result, "engine_version")).to be_unknown
    end

    it "does not report a generic timeout" do
      expect(check(result, "docker_daemon").detail).not_to match(/\Atimeout\z/i)
    end

    it "distinguishes a slow daemon from an absent one" do
      slow = run(engine_info: SwarmBootstrap::EngineError.new(SwarmBootstrap::DAEMON_TIMEOUT,
        "docker info failed: timed out after 20s"))

      expect(check(slow, "docker_daemon").detail).to include(SwarmBootstrap::DAEMON_TIMEOUT)
      expect(check(slow, "docker_daemon").detail).not_to include(SwarmBootstrap::DAEMON_UNREACHABLE)
    end
  end

  # AC5. The choice is the operator's, and the report is what puts the candidates
  # in front of them.
  describe "the advertise address" do
    let(:eth0) { SystemProbe::Interface.new(name: "eth0", address: "10.0.0.5", loopback: false, private: true) }
    let(:eth1) { SystemProbe::Interface.new(name: "eth1", address: "192.168.9.9", loopback: false, private: true) }
    let(:loopback) { SystemProbe::Interface.new(name: "lo", address: "127.0.0.1", loopback: true, private: false) }

    it "suggests the only candidate when there is exactly one" do
      result = run(probe: HealthyProbe.new(interfaces: [ loopback, eth0 ]))

      expect(result.suggested_advertise_address).to eq("10.0.0.5")
      expect(result).not_to be_advertise_address_required
    end

    it "requires a choice when there is more than one, and suggests nothing" do
      result = run(probe: HealthyProbe.new(interfaces: [ loopback, eth0, eth1 ]))

      expect(result).to be_advertise_address_required
      expect(result.suggested_advertise_address).to be_nil
      expect(check(result, "advertise_address")).to be_unknown
      expect(check(result, "advertise_address").detail).to include("10.0.0.5", "192.168.9.9")
    end

    # A Swarm advertised on loopback cannot be joined, and finding that out when
    # the second node arrives means rebuilding the cluster.
    it "never offers loopback as a candidate" do
      result = run(probe: HealthyProbe.new(interfaces: [ loopback, eth0 ]))

      expect(result.advertise_candidates.map(&:address)).to eq([ "10.0.0.5" ])
    end
  end
end
