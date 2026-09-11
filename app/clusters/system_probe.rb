require "English"
require "etc"
require "open3"
require "resolv"
require "socket"

# What the preflight needs to know about the machine it is about to turn into
# the first node.
#
# ## Why this is a separate object
#
# It is the adapter between the domain and an external API — the operating
# system — in the same sense a provider adapter isolates a vendor SDK
# (`AGENT_RULES`, "Provider adapters"). The concrete pressure is AC4: a clock out
# of sync, an occupied port and an incompatible Engine version must **block**
# the bootstrap with a specific diagnosis, and there is no way to see those
# branches fail on a machine where the clock is fine and the ports are free.
# With the probe as a collaborator, every failing branch is exercised; without
# it, the only tests possible are the ones that pass here today.
#
# It is not a speculative extension point. It has exactly the methods the checks
# of doc 06 §3.2 need, and nothing is here "in case".
#
# ## Every method is total
#
# A probe that raises turns a preflight check into an exception three layers up.
# When the platform cannot answer, the method says so — `nil`, or a result
# marked unknown — and the check reports UNKNOWN rather than passing. doc 06
# §3.1 says the installer aborts on conditions it cannot verify; reporting
# "unknown" is how that decision reaches the operator instead of being made
# silently here.
class SystemProbe
  SUPPORTED_OPERATING_SYSTEMS = %w[linux darwin].freeze
  SUPPORTED_ARCHITECTURES = %w[x86_64 amd64 aarch64 arm64].freeze

  # doc 06 §4.1, the ports a Swarm manager needs on the first node.
  SWARM_PORTS = [
    { port: 2377, protocol: :tcp, use: "Swarm control plane and node join" },
    { port: 7946, protocol: :tcp, use: "node-to-node discovery" },
    { port: 7946, protocol: :udp, use: "node-to-node discovery" },
    { port: 4789, protocol: :udp, use: "VXLAN overlay data path" }
  ].freeze

  # Enough for images, layers and the platform's own volumes on a first node.
  MINIMUM_FREE_BYTES = 10 * 1024 * 1024 * 1024
  MINIMUM_FREE_INODES = 100_000

  # A network address the operator could advertise on.
  Interface = Data.define(:name, :address, :loopback, :private) do
    def loopback? = loopback
    def private? = private
    # Loopback cannot be reached by another node, so it is never a candidate
    # even on a single-node cluster: the Swarm that grows to two nodes would
    # have to be rebuilt.
    def advertisable? = !loopback?
  end

  def operating_system = RbConfig::CONFIG["host_os"].to_s.downcase.sub(/\d+(\.\d+)*$/, "")

  def architecture = RbConfig::CONFIG["host_cpu"].to_s.downcase

  def supported_platform?
    SUPPORTED_OPERATING_SYSTEMS.any? { |name| operating_system.include?(name) } &&
      SUPPORTED_ARCHITECTURES.include?(architecture)
  end

  def hostname = Socket.gethostname

  # Whether this machine can resolve its own name. A node that cannot is a node
  # whose certificates and logs disagree with everything else about who it is.
  def hostname_resolves?
    Resolv.getaddress(hostname)
    true
  rescue Resolv::ResolvError, Resolv::ResolvTimeout
    # `/etc/hosts` is not always visible to Resolv's default config; falling
    # back to the system resolver keeps a correctly configured machine from
    # failing a check about configuration it has.
    begin
      !Addrinfo.getaddrinfo(hostname, nil).empty?
    rescue SocketError
      false
    end
  end

  # Every address of this machine, so the operator can choose (AC5).
  #
  # `nil` — not `[]` — when the list cannot be enumerated. The two are different
  # answers and the check treats them differently: an empty list means this
  # machine has no address another node could reach, which blocks; a nil means
  # nobody knows, which is reported as unknown. Collapsing them was the first
  # version, and the custom `Opanel/SilentRescue` cop refused it.
  def interfaces
    Socket.getifaddrs.filter_map do |entry|
      address = entry.addr
      next unless address&.ip?
      next if address.ipv6?

      Interface.new(
        name: entry.name,
        address: address.ip_address,
        loopback: address.ipv4_loopback?,
        private: address.ipv4_private?
      )
    end.uniq { |interface| interface.address }
  rescue SystemCallError
    nil
  end

  # Free bytes and inodes on the filesystem holding Docker's data. `nil` when the
  # platform will not say, **or when the path is not on this host** — reported as
  # unknown, never as enough.
  #
  # The path matters more than it looks. Measuring `/` was wrong on the machine
  # this was written on: macOS mounts a sealed read-only system volume there, so
  # the probe reported 4.7 GB free and the check failed a bootstrap that had
  # hundreds of gigabytes available where Docker actually writes. The caller
  # passes Docker's own data root; when the Engine runs in a VM that directory
  # does not exist here, and "I cannot measure it" is the honest answer.
  def free_disk_bytes(path) = statfs(path)&.fetch(:bytes, nil)
  def free_inodes(path) = statfs(path)&.fetch(:inodes, nil)

  def path_on_this_host?(path) = path.present? && File.directory?(path)

  # `nil` when the machine will not say whether its clock is disciplined.
  #
  # Deliberately asks the platform's own time daemon rather than reaching the
  # network: a preflight that needs egress to pass is a preflight that fails on
  # an air-gapped install for the wrong reason.
  def clock_synchronized?
    case operating_system
    when /linux/ then linux_clock_synchronized?
    when /darwin/ then darwin_clock_synchronized?
    end
  end

  # Whether something is already listening. A port the Swarm needs and cannot
  # have blocks the bootstrap, naming the port (AC4).
  def port_free?(port, protocol: :tcp)
    protocol == :udp ? udp_port_free?(port) : tcp_port_free?(port)
  end

  # What holds the port, when the platform will say. Used only to make the
  # diagnosis actionable; absence of an answer is not a failure of the check.
  def port_holder(port)
    stdout, _stderr, status = Open3.capture3("lsof", "-nP", "-i", ":#{port}", "-sTCP:LISTEN", "-t")
    return nil unless status&.success?

    pid = stdout.lines.first.to_s.strip
    return nil if pid.empty?

    name, _stderr, ok = Open3.capture3("ps", "-p", pid, "-o", "comm=")
    ok&.success? ? "#{name.strip} (pid #{pid})" : "pid #{pid}"
  rescue Errno::ENOENT
    nil
  end

  private

  def tcp_port_free?(port)
    server = TCPServer.new("0.0.0.0", port)
    server.close
    true
  rescue Errno::EADDRINUSE, Errno::EACCES
    false
  rescue StandardError
    # Could not decide. Answering `true` would let an occupied port through, so
    # the check treats a nil-ish outcome as "unknown" — see `Preflight`.
    nil
  end

  def udp_port_free?(port)
    socket = UDPSocket.new
    socket.bind("0.0.0.0", port)
    socket.close
    true
  rescue Errno::EADDRINUSE, Errno::EACCES
    false
  rescue StandardError
    nil
  end

  # `df` rather than a gem: one call does not justify a dependency, and
  # `AGENT_RULES` asks that question before every addition. Parsed defensively —
  # an unexpected format answers nil, which the check reports as unknown rather
  # than as enough.
  def statfs(path)
    return nil unless path_on_this_host?(path)

    stdout, _stderr, status = Open3.capture3("df", "-k", "-i", path)
    return nil unless status&.success?

    fields = stdout.lines.last.to_s.split
    available_kb = fields.find { |field| field.match?(/\A\d+\z/) && fields.index(field) >= 3 }
    inodes = fields[6]

    return nil if available_kb.nil?

    { bytes: available_kb.to_i * 1024, inodes: inodes.to_s.match?(/\A\d+\z/) ? inodes.to_i : nil }
  rescue Errno::ENOENT
    nil
  end

  def linux_clock_synchronized?
    stdout, _stderr, status = Open3.capture3("timedatectl", "show", "-p", "NTPSynchronized", "--value")
    return nil unless status&.success?

    stdout.strip == "yes"
  rescue Errno::ENOENT
    nil
  end

  # `systemsetup` exits **0** while refusing: without root it prints
  # "You need administrator access to run this tool... exiting!" and succeeds.
  # Reading that as "not synchronized" was a false FAIL that blocked the
  # bootstrap on a perfectly healthy machine — found by running the probe against
  # this one. So the answer is only trusted when the output actually says On or
  # Off; anything else is unknown, and the check reports it as such.
  def darwin_clock_synchronized?
    stdout, _stderr, status = Open3.capture3("systemsetup", "-getusingnetworktime")
    return nil unless status&.success?

    return true if stdout.match?(/Network Time:\s*On/i)
    return false if stdout.match?(/Network Time:\s*Off/i)

    nil
  rescue Errno::ENOENT
    nil
  end
end
