require "json"
require "open3"
require "timeout"

# The one path in the application that speaks to the Docker Engine (AC8).
#
# It lives under `app/executors/` because that is the only directory AF-02 lets
# reach the Engine, and adding another is a Tier-0 security change requiring an
# ADR (Annex C §8). The full Swarm Executor — the typed allowlist covering every
# runtime operation — is `M01-09`; this is the minimum `M01-08` needs and nothing
# more.
#
# ## There is no `exec(command:)` here, and there never will be
#
# Every method below is a named operation with typed arguments. A generic
# escape hatch would make the allowlist decorative: the point of a single
# privileged boundary is that reading this file tells you the complete set of
# things the platform can do to the Engine.
#
# ## The join token is material, not output
#
# `docker swarm init` prints the worker join token in its success message. A token
# that reaches a log, an exception, an audit record or a response is a token that
# lets anyone who reads it join the cluster (doc 04 §14.2, AC10). So the raw
# output of a mutating call **never leaves this class**: `init` returns the Swarm
# id it looked up afterwards, and every error string is scrubbed before it is
# raised. Scrubbing on the way out rather than at each call site is the only
# version of this that stays true.
#
# ## The socket stays local, and that is checked rather than assumed
#
# doc 06 §4.2: the socket stays local to authorized administrative components and
# the daemon is never reached over the network.
#
# **Not setting `DOCKER_HOST` is not the same as not having one.** `Open3.capture3`
# inherits the process environment, so an ambient `DOCKER_HOST` — or a
# `docker context` pointing elsewhere — silently redirects every operation here,
# `swarm init` included, at a remote Engine. The first version of this class
# claimed the local socket was "the only destination by construction" and it was
# not: the independent review reproduced it by exporting
# `DOCKER_HOST=tcp://192.0.2.1:2375` and watching a real call dial out.
#
# So the effective endpoint is **resolved and refused** before any command runs,
# the same way `lib/gates/swarm_lab.rb` protects the disposable lab. A scheme that
# is not a local socket fails closed with its own classified cause.
class SwarmBootstrap
  # A failure that is the Engine's, not the caller's. Carries a **classified**
  # cause because the Story's Observability Requirements refuse a generic timeout:
  # an operator has to know whether the daemon is absent, refusing, or slow.
  class EngineError < StandardError
    attr_reader :cause_code

    def initialize(cause_code, message)
      @cause_code = cause_code
      super(message)
    end
  end

  # Why the Engine could not be reached or would not act. These are the values
  # that reach `Cluster#unreachable_reason` and the UI.
  DAEMON_UNREACHABLE = "DAEMON_UNREACHABLE"
  DAEMON_PERMISSION_DENIED = "DAEMON_PERMISSION_DENIED"
  DAEMON_TIMEOUT = "DAEMON_TIMEOUT"
  SWARM_INIT_REFUSED = "SWARM_INIT_REFUSED"
  # The destination is not a socket on this machine. Refused before anything
  # runs, because a redirected `swarm init` builds somebody else's cluster.
  DAEMON_NOT_LOCAL = "DAEMON_NOT_LOCAL"
  # The destination could not be established. Distinct from "the destination is
  # wrong": both refuse, and only this one means we do not know what we would be
  # talking to.
  DAEMON_ENDPOINT_UNKNOWN = "DAEMON_ENDPOINT_UNKNOWN"
  UNCLASSIFIED = "UNCLASSIFIED"

  # A socket on this machine. `tcp://` and `ssh://` are refused outright: doc 06
  # §4.2 says remote multi-cluster access "exigirá um mecanismo seguro próprio no
  # futuro; não será resolvido simplesmente abrindo Docker API na internet", so
  # until that mechanism exists there is no legitimate remote destination.
  LOCAL_SCHEMES = %w[unix npipe].freeze

  # `unix:///var/run/docker.sock`, `tcp://127.0.0.1:2375`, `ssh://user@host`. A
  # value with no scheme is not parsed into a guess: not knowing what an endpoint
  # means is a reason to refuse it.
  ENDPOINT = %r{\A(?<scheme>[a-z][a-z0-9+.\-]*)://}i

  # A slow daemon is a failure with a name, not a hang. The bootstrap screen has
  # to come back and say so.
  DEFAULT_TIMEOUT_SECONDS = 20

  # Anything shaped like a Swarm join token. Docker's tokens are
  # `SWMTKN-1-<base64ish>-<base64ish>`; the pattern is deliberately loose on the
  # tail so a format change still matches the prefix.
  JOIN_TOKEN = /SWMTKN-\S+/

  REDACTED = "[REDACTED]"

  # What the Engine says when it is not there to answer. Named rather than
  # inlined so the three ways Docker phrases the same condition stay together.
  DAEMON_ABSENT = /cannot connect to the docker daemon|is the docker daemon running|no such file or directory/i
  DAEMON_REFUSING = /permission denied|dial unix.*permission/i
  SWARM_REFUSING = /swarm|node is already part of/i

  # What the Engine says about itself. A Struct rather than a Hash so a typo in a
  # key is a NoMethodError here instead of a nil three layers up.
  Info = Struct.new(:engine_version, :swarm_state, :swarm_id, :node_id, :manager?,
    :node_count, :data_root, keyword_init: true) do
    def swarm_active? = swarm_state == "active"
    def swarm_inactive? = swarm_state == "inactive"
  end

  class << self
    # Everything the preflight and the status refresh need, in one call. Raises
    # `EngineError` with a classified cause when the daemon cannot answer.
    def info(timeout: DEFAULT_TIMEOUT_SECONDS)
      payload = JSON.parse(run!("info", "--format", "{{json .}}", timeout: timeout))

      Info.new(
        engine_version: payload["ServerVersion"],
        swarm_state: payload.dig("Swarm", "LocalNodeState"),
        swarm_id: payload.dig("Swarm", "Cluster", "ID"),
        node_id: payload.dig("Swarm", "NodeID").presence,
        manager?: payload.dig("Swarm", "ControlAvailable") == true,
        node_count: payload.dig("Swarm", "Nodes"),
        # Where the Engine writes. The disk check has to measure *this*
        # filesystem, not `/` — and when the Engine runs in a VM this path does
        # not exist on the host at all, which the check reports as unknown rather
        # than measuring the wrong volume.
        data_root: payload["DockerRootDir"]
      )
    rescue JSON::ParserError => error
      # The daemon answered with something that is not JSON. Naming that is more
      # useful than letting a parse error surface three layers up, and the raw
      # body is not repeated — it may carry anything.
      raise EngineError.new(UNCLASSIFIED, "the Docker daemon returned an unreadable response: #{error.class}")
    end

    # Whether the Engine is answering at all. Never raises: the caller is a
    # preflight check, and a check that explodes is a check somebody rescues into
    # `true`.
    def reachable?
      info
      true
    rescue EngineError
      false
    end

    # `docker swarm init`, with the advertise address stated explicitly.
    #
    # Explicit and required, never inferred (AC5, doc 06 §3.3): on a machine with
    # several interfaces Docker picks one, and the one it picks is the one the
    # other nodes cannot reach. The choice is the operator's, and the preflight is
    # what puts the candidates in front of them.
    #
    # Returns the Swarm id read back from the Engine. **The command's own output
    # is discarded**, because that is where the join token is.
    def init(advertise_address:, timeout: DEFAULT_TIMEOUT_SECONDS)
      raise ArgumentError, "an advertise address is required" if advertise_address.to_s.strip.empty?

      run!("swarm", "init", "--advertise-addr", advertise_address.to_s, timeout: timeout)

      # Read back rather than parsed out of the success message: the id is a fact
      # about the daemon, and the message is prose that carries a credential.
      info(timeout: timeout).swarm_id
    end

    # Marks this node so the Cluster's own resources can be found after a full
    # Control Plane restart (the ownership labels of `M01-16` build on this).
    def label_node(node_id:, key:, value:, timeout: DEFAULT_TIMEOUT_SECONDS)
      run!("node", "update", "--label-add", "#{key}=#{value}", node_id, timeout: timeout)
      true
    end

    # Removes every trace of a token from anything about to be logged, raised or
    # persisted. Public because the Command's error path formats messages too, and
    # a redaction only one caller remembers is not a redaction.
    def redact(text)
      text.to_s.gsub(JOIN_TOKEN, REDACTED)
    end

    # Where the `docker` CLI would actually connect: `DOCKER_HOST` when it is set,
    # otherwise the endpoint of the current context. Reading the variable alone is
    # not enough — `docker context use production` leaves it empty.
    #
    # Public so a diagnostic screen can say what it would talk to without having
    # to run a command first.
    def endpoint
      from_environment = ENV.fetch("DOCKER_HOST", "").strip
      return from_environment unless from_environment.empty?

      named = ENV.fetch("DOCKER_CONTEXT", "").strip
      arguments = [ "context", "inspect", "--format", "{{.Endpoints.docker.Host}}" ]
      arguments << named unless named.empty?

      stdout, stderr, status = Open3.capture3("docker", *arguments)
      unless status&.success?
        raise EngineError.new(DAEMON_ENDPOINT_UNKNOWN,
          "DOCKER_HOST is unset and the current Docker context could not be read " \
          "(#{stderr.to_s.lines.first.to_s.strip}). The destination is unknown, so it is refused.")
      end

      stdout.strip
    rescue Errno::ENOENT
      raise EngineError.new(DAEMON_UNREACHABLE, "the docker executable is not on PATH")
    end

    private

    # Fails closed, before anything runs. This is AC8 held by a check rather than
    # by a comment.
    def assert_local_endpoint!
      raw = endpoint
      scheme = raw[ENDPOINT, :scheme]&.downcase

      if scheme.nil?
        raise EngineError.new(DAEMON_ENDPOINT_UNKNOWN,
          "cannot tell what #{raw.inspect} points at, so it is refused")
      end

      return if LOCAL_SCHEMES.include?(scheme)

      raise EngineError.new(DAEMON_NOT_LOCAL,
        "the Docker endpoint #{raw.inspect} is not a socket on this machine. " \
        "doc 06 §4.2 keeps the daemon off the network; unset DOCKER_HOST or switch " \
        "to a local context.")
    end

    # The only place a Docker process is started.
    def run!(*arguments, timeout:)
      assert_local_endpoint!

      stdout, stderr, status = capture(arguments, timeout)

      return stdout.strip if status&.success?

      raise EngineError.new(classify(stderr, status), redact(failure_message(arguments, stderr)))
    end

    def capture(arguments, timeout)
      Timeout.timeout(timeout) do
        # No `-H` is passed; the destination is whatever the environment resolves
        # to, and `assert_local_endpoint!` has already refused anything that is
        # not a socket on this machine.
        Open3.capture3("docker", *arguments)
      end
    rescue Timeout::Error
      [ "", "timed out after #{timeout}s", nil ]
    rescue Errno::ENOENT
      [ "", "the docker executable is not on PATH", nil ]
    end

    # A cause an operator can act on. The Story's Observability Requirements make
    # this mandatory: *"não como timeout genérico"*.
    def classify(stderr, status)
      text = stderr.to_s

      return DAEMON_TIMEOUT if status.nil? && text.include?("timed out")
      return DAEMON_UNREACHABLE if status.nil?
      return DAEMON_UNREACHABLE if text.match?(DAEMON_ABSENT)
      return DAEMON_PERMISSION_DENIED if text.match?(DAEMON_REFUSING)
      return SWARM_INIT_REFUSED if text.match?(SWARM_REFUSING)

      UNCLASSIFIED
    end

    # Names the operation, never the whole command line, and carries the Engine's
    # own first line so the cause is not lost. Scrubbed by `run!` before it is
    # raised.
    def failure_message(arguments, stderr)
      operation = arguments.take(2).join(" ")
      detail = stderr.to_s.lines.first.to_s.strip

      detail.empty? ? "docker #{operation} failed" : "docker #{operation} failed: #{detail}"
    end
  end
end
