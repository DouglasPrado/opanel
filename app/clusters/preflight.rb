require "yaml"

# The preflight checks of doc 06 §3.2, run before a machine becomes the first
# node (AC3).
#
# ## Three outcomes, not two
#
# A check is `PASS`, `FAIL` or `UNKNOWN`. The third is the one that matters:
# doc 06 §3.1 says the installer *"deve abortar quando detectar condições
# inseguras ou incompatíveis"*, and a condition it could not evaluate is not a
# condition it verified. Collapsing UNKNOWN into PASS is how a bootstrap proceeds
# on a machine nobody checked; collapsing it into FAIL is how a correct machine is
# refused for a reason that is not about it. So it is reported as itself, and the
# operator decides.
#
# Only `FAIL` blocks. `UNKNOWN` is surfaced on the screen next to what it could
# not determine and why.
#
# ## Every check answers individually
#
# AC3 asks for each check reported on its own. A single boolean would tell the
# operator that something is wrong and nothing about what, which is the failure
# mode doc 06 §14.1 spends a section rejecting for readiness.
class Preflight
  PASS = "PASS"
  FAIL = "FAIL"
  UNKNOWN = "UNKNOWN"

  # Must agree with `engine.minimum_version` in
  # `config/architecture/docker-lab.yml`, which records the version the platform
  # is developed against. Declared here rather than read from there because an
  # application class should not depend on the test harness's configuration —
  # `spec/unit/preflight_spec.rb` asserts the two are the same number, so they
  # cannot drift in silence.
  MINIMUM_ENGINE_VERSION = "24.0"

  # One line of the report.
  Check = Data.define(:name, :status, :detail) do
    def pass? = status == PASS
    def fail? = status == FAIL
    def unknown? = status == UNKNOWN
  end

  Result = Data.define(:checks, :interfaces, :engine) do
    # What AC4 turns on: a failing check stops the bootstrap.
    def blocked? = checks.any?(&:fail?)
    def failures = checks.select(&:fail?)
    def unknowns = checks.select(&:unknown?)

    # Addresses another node could reach. Loopback is excluded even on a
    # single-node cluster: a Swarm advertised on 127.0.0.1 cannot grow, and
    # discovering that later means rebuilding it.
    #
    # Empty when the machine has none *and* when the list could not be
    # enumerated; `interfaces_known?` is what separates the two.
    def interfaces_known? = !interfaces.nil?
    def advertise_candidates = (interfaces || []).select(&:advertisable?)

    # AC5. With more than one candidate the operator chooses; with exactly one
    # there is nothing to choose, and demanding a choice anyway is ceremony.
    def advertise_address_required? = advertise_candidates.length > 1
    def suggested_advertise_address = advertise_candidates.length == 1 ? advertise_candidates.first.address : nil
  end

  def self.call(probe: SystemProbe.new, executor: SwarmBootstrap)
    new(probe: probe, executor: executor).call
  end

  def initialize(probe: SystemProbe.new, executor: SwarmBootstrap)
    @probe = probe
    @executor = executor
  end

  def call
    engine = engine_info

    Result.new(
      checks: [
        platform_check,
        hostname_check,
        daemon_check(engine),
        engine_version_check(engine),
        engine_locality_check(engine),
        clock_check,
        *disk_checks(engine),
        *port_checks(engine),
        advertise_check(engine)
      ],
      interfaces: probe.interfaces,
      engine: engine
    )
  end

  private

  attr_reader :probe, :executor

  # Asked once. Every Docker-dependent check reads this, so a slow daemon costs
  # one timeout rather than one per check — and every one of them sees the same
  # observation rather than a set that could disagree with itself.
  def engine_info
    executor.info
  rescue SwarmBootstrap::EngineError => error
    error
  end

  def engine_reachable?(engine) = !engine.is_a?(SwarmBootstrap::EngineError)

  # Whether the Engine runs on the machine this process is measuring.
  #
  # It usually does — doc 06 §3.1 describes turning *"uma máquina Linux limpa"*
  # into the first node — and then every check below is about the right host. On
  # a developer's Docker Desktop the Engine lives in a VM, and the host's free
  # ports, free disk and network interfaces say nothing about where the Swarm will
  # actually listen, write and advertise.
  #
  # Establishing it once, from the Engine's own data directory, is what keeps
  # those checks from reporting PASS about the wrong machine. Running the
  # preflight here was what exposed it: the host reported 2377/tcp free while the
  # Swarm was active and listening on it inside the VM.
  def engine_local?(engine)
    engine_reachable?(engine) && probe.path_on_this_host?(engine.data_root)
  end

  NOT_LOCAL = "the Docker Engine does not run on this host, so this cannot be measured here"

  def engine_locality_check(engine)
    return check("engine_locality", UNKNOWN, "the daemon did not answer") unless engine_reachable?(engine)

    if probe.path_on_this_host?(engine.data_root)
      check("engine_locality", PASS, "the Engine writes to #{engine.data_root} on this host")
    else
      # Not a FAIL: a remote or VM-backed Engine is a legitimate development
      # setup. It is reported so the operator knows why four checks below could
      # not be evaluated.
      check("engine_locality", UNKNOWN,
        "the Engine reports #{engine.data_root}, which is not on this host — ports, disk and " \
        "interfaces below cannot be measured from here")
    end
  end

  def platform_check
    if probe.supported_platform?
      check("operating_system", PASS, "#{probe.operating_system} #{probe.architecture}")
    else
      check("operating_system", FAIL,
        "#{probe.operating_system} #{probe.architecture} is not a supported platform " \
        "(#{SystemProbe::SUPPORTED_OPERATING_SYSTEMS.join(', ')} on " \
        "#{SystemProbe::SUPPORTED_ARCHITECTURES.join(', ')})")
    end
  end

  def hostname_check
    if probe.hostname_resolves?
      check("hostname", PASS, probe.hostname)
    else
      check("hostname", FAIL,
        "#{probe.hostname} does not resolve on this machine; certificates and logs " \
        "will disagree with the node's own name")
    end
  end

  # AC7: the cause is classified, never a generic timeout.
  def daemon_check(engine)
    return check("docker_daemon", PASS, "Engine #{engine.engine_version}") if engine_reachable?(engine)

    check("docker_daemon", FAIL, "#{engine.cause_code}: #{engine.message}")
  end

  # AC4: an incompatible Engine blocks, naming both versions.
  def engine_version_check(engine)
    unless engine_reachable?(engine)
      return check("engine_version", UNKNOWN, "the daemon did not answer, so its version is unknown")
    end

    found = engine.engine_version.to_s
    if found.empty?
      check("engine_version", UNKNOWN, "the daemon did not report a version")
    elsif Gem::Version.new(found.split("-").first) >= Gem::Version.new(MINIMUM_ENGINE_VERSION)
      check("engine_version", PASS, found)
    else
      check("engine_version", FAIL,
        "Docker Engine #{found} is below the supported minimum #{MINIMUM_ENGINE_VERSION}")
    end
  rescue ArgumentError
    check("engine_version", UNKNOWN, "the daemon reported an unreadable version: #{engine.engine_version.inspect}")
  end

  # AC4. A skewed clock breaks TLS, Raft and every correlation by timestamp, and
  # it breaks them in ways that look like something else.
  def clock_check
    case probe.clock_synchronized?
    when true then check("clock", PASS, "synchronized")
    when false then check("clock", FAIL,
      "the system clock is not synchronized; TLS handshakes, Swarm consensus and log " \
      "correlation all depend on it")
    else check("clock", UNKNOWN,
      "this machine will not say whether its clock is disciplined — check the time daemon by hand")
    end
  end

  # Measured on the filesystem the Engine actually writes to, which is not `/`.
  # When the Engine runs in a VM that directory is not on this host and the check
  # says so rather than measuring the wrong volume.
  def disk_checks(engine)
    unless engine_local?(engine)
      reason = engine_reachable?(engine) ? NOT_LOCAL : "the daemon did not answer"
      return [ check("disk_space", UNKNOWN, reason), check("inodes", UNKNOWN, reason) ]
    end

    [ disk_space_check(engine.data_root), inodes_check(engine.data_root) ]
  end

  def disk_space_check(root)
    bytes = probe.free_disk_bytes(root)

    if bytes.nil?
      check("disk_space", UNKNOWN, "could not measure free space on #{root}")
    elsif bytes >= SystemProbe::MINIMUM_FREE_BYTES
      check("disk_space", PASS, "#{human_bytes(bytes)} free on #{root}")
    else
      check("disk_space", FAIL,
        "#{human_bytes(bytes)} free on #{root}, below the #{human_bytes(SystemProbe::MINIMUM_FREE_BYTES)} minimum")
    end
  end

  def inodes_check(root)
    inodes = probe.free_inodes(root)

    if inodes.nil?
      check("inodes", UNKNOWN, "could not measure free inodes on #{root}")
    elsif inodes >= SystemProbe::MINIMUM_FREE_INODES
      check("inodes", PASS, "#{inodes} free on #{root}")
    else
      check("inodes", FAIL,
        "#{inodes} free inodes on #{root}, below the #{SystemProbe::MINIMUM_FREE_INODES} minimum")
    end
  end

  # One check per port, named (AC3, AC4). doc 06 §4.1 is the list.
  def port_checks(engine)
    SystemProbe::SWARM_PORTS.map do |entry|
      name = "port_#{entry[:port]}_#{entry[:protocol]}"

      next check(name, UNKNOWN, NOT_LOCAL) unless engine_local?(engine)

      case probe.port_free?(entry[:port], protocol: entry[:protocol])
      when true then check(name, PASS, "free — #{entry[:use]}")
      when false then check(name, FAIL, port_taken_detail(entry))
      else check(name, UNKNOWN, "could not determine whether #{entry[:port]}/#{entry[:protocol]} is free")
      end
    end
  end

  def port_taken_detail(entry)
    holder = entry[:protocol] == :tcp ? probe.port_holder(entry[:port]) : nil
    by = holder ? " held by #{holder}" : ""

    "#{entry[:port]}/#{entry[:protocol]} is already in use#{by}; the Swarm needs it for #{entry[:use]}"
  end

  # AC5. Never guesses: with several candidates the operator has to choose, and a
  # machine with none cannot host a Swarm another node could ever join.
  def advertise_check(engine)
    return check("advertise_address", UNKNOWN, NOT_LOCAL) unless engine_local?(engine)

    found = probe.interfaces
    if found.nil?
      return check("advertise_address", UNKNOWN, "this machine's network interfaces could not be listed")
    end

    candidates = found.select(&:advertisable?)

    case candidates.length
    when 0 then check("advertise_address", FAIL,
      "no non-loopback address was found; a Swarm advertised on loopback cannot be joined")
    when 1 then check("advertise_address", PASS,
      "#{candidates.first.address} on #{candidates.first.name}")
    else check("advertise_address", UNKNOWN,
      "#{candidates.length} candidates (#{candidates.map(&:address).join(', ')}) — choose one explicitly")
    end
  end

  def check(name, status, detail) = Check.new(name: name, status: status, detail: detail)

  def human_bytes(bytes) = "#{(bytes.to_f / (1024**3)).round(1)} GB"
end
