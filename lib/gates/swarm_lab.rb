# frozen_string_literal: true

require "ipaddr"
require "json"
require "open3"
require "resolv"
require "yaml"

module Opanel
  module Gates
    # The disposable Docker/Swarm laboratory.
    #
    # Runtime behaviour has to be tested against a real Engine (Annex D §7): a
    # mock agrees with whatever the code believes, which is the belief under test.
    #
    # **The guardrail is the important part.** The autonomous loop must never be
    # able to reach a production cluster (Annex H §12.2), and a check that can be
    # switched off with an environment variable is not a check. So the lab is
    # identified by a property of the *daemon itself* — a node label this tool
    # applied — and every mutation verifies it first. Pointing at another daemon
    # fails closed, before anything is created or destroyed.
    module SwarmLab
      class NotTheLab < StandardError; end
      class DockerUnavailable < StandardError; end
      # The destination could not be established. Distinct from "the destination
      # is wrong": both refuse, but only this one means the tool does not know
      # what it is talking to.
      class EndpointUnknown < StandardError; end
      # A listing failed, so what the lab contains is not known. Distinct from
      # "the lab contains nothing".
      class InventoryUnknown < StandardError; end

      Status = Struct.new(:available, :swarm_state, :is_lab, :engine_version, :api_version,
        :node_count, :services, :orphans, :endpoint, :inventory_reason, :reason, keyword_init: true) do
        def available? = available
        def lab? = is_lab
        # Nil is not empty. `status` reports what it could not determine rather
        # than printing "none".
        def inventory_known? = inventory_reason.nil?
      end

      module_function

      def config(root = Dir.pwd)
        @config ||= YAML.safe_load_file(File.join(root, "config/architecture/docker-lab.yml"))
      end

      def label(root = Dir.pwd) = config(root).dig("lab", "label")
      def resource_prefix(root = Dir.pwd) = config(root).dig("lab", "resource_prefix")
      def minimum_version(root = Dir.pwd) = config(root).dig("engine", "minimum_version")

      def image(root = Dir.pwd)
        ENV.fetch("OPANEL_LAB_IMAGE") { config(root).dig("lab", "image") }
      end

      # Present on this node. A Swarm service can only start from an image the
      # node already has when there is no registry to reach.
      def image_available?(root = Dir.pwd)
        _stdout, _stderr, status = docker("image", "inspect", image(root))
        status.success?
      end

      def docker(*arguments)
        Open3.capture3("docker", *arguments)
      end

      def docker!(*arguments)
        stdout, stderr, status = docker(*arguments)
        raise DockerUnavailable, stderr.strip unless status.success?

        stdout.strip
      end

      # `docker secret create` and `docker config create` read the payload from
      # stdin. Passing a path instead would put the value on somebody's disk,
      # which is the thing a Swarm secret exists to avoid.
      def docker_input(*arguments, input:)
        Open3.capture3("docker", *arguments, stdin_data: input)
      end

      # Removing something that is already gone is the desired state, not a
      # failure. Anything else is: a resource that would not delete is the next
      # run's inherited state.
      ALREADY_GONE = /not found|no such/i

      def remove(kind, name)
        _stdout, stderr, status = docker(kind, "rm", name)
        return nil if status.success? || stderr.match?(ALREADY_GONE)

        "#{kind} #{name}: #{stderr.strip}"
      end

      def available?
        _stdout, _stderr, status = docker("info", "--format", "{{.ServerVersion}}")
        status.success?
      end

      # Everything `bin/swarm-lab status` reports, and what the guardrail reads.
      def status(root = Dir.pwd)
        unless available?
          return Status.new(available: false, reason: "the Docker daemon is not reachable")
        end

        info = JSON.parse(docker!("info", "--format", "{{json .}}"))
        version = JSON.parse(docker!("version", "--format", "{{json .}}"))
        swarm_state = info.dig("Swarm", "LocalNodeState")

        # An unknown inventory is reported as unknown. `services: []` and
        # "the listing failed" are different facts and only one of them is safe
        # to act on.
        services, orphans, inventory_reason =
          begin
            [ lab_services(root), orphaned_resources(root), nil ]
          rescue InventoryUnknown, DockerUnavailable => error
            [ nil, nil, error.message ]
          end

        Status.new(
          available: true,
          swarm_state: swarm_state,
          is_lab: lab_daemon?(root),
          engine_version: info["ServerVersion"],
          api_version: version.dig("Server", "ApiVersion"),
          node_count: info.dig("Swarm", "Nodes"),
          services: services,
          orphans: orphans,
          endpoint: (begin
            resolved_endpoint(root).raw
          rescue EndpointUnknown
            nil
          end),
          inventory_reason: inventory_reason
        )
      end

      # The guardrail. A daemon is the lab only if a node carries the label this
      # tool applied — which no production cluster will.
      def lab_daemon?(root = Dir.pwd)
        stdout, _stderr, status = docker(
          "node", "inspect", "self", "--format", "{{index .Spec.Labels \"#{label(root)}\"}}"
        )
        status.success? && stdout.strip == "true"
      rescue DockerUnavailable
        false
      end

      # --- The destination ------------------------------------------------------
      #
      # Which daemon `docker` in this process would actually talk to. Reading
      # DOCKER_HOST alone answered a different question: the CLI falls back to the
      # **current context** when the variable is unset, so `docker context use
      # production` left DOCKER_HOST empty and this code called the destination
      # local. That is the machine `swarm init` would then have run against.
      #
      # Precedence is the CLI's own: DOCKER_HOST wins, otherwise the context named
      # by DOCKER_CONTEXT, otherwise the current context.
      Endpoint = Struct.new(:raw, :scheme, :host, :source, keyword_init: true) do
        def to_s = "#{raw} (from #{source})"
      end

      # `unix:///var/run/docker.sock`, `tcp://127.0.0.1:2375`, `tcp://[::1]:2375`,
      # `ssh://user@host`. A value without a scheme is not parsed into a guess:
      # not knowing what an endpoint means is a reason to refuse it.
      ENDPOINT = %r{\A(?<scheme>[a-z][a-z0-9+.\-]*)://(?<authority>[^/?#]*)}i

      def parse_endpoint(raw, source:)
        value = raw.to_s.strip
        match = ENDPOINT.match(value)
        raise EndpointUnknown, "cannot parse the Docker endpoint #{raw.inspect} (from #{source})" if match.nil?

        authority = match[:authority].to_s.sub(/\A[^@]*@/, "")
        host =
          if (bracketed = authority[/\A\[([^\]]+)\]/, 1])
            bracketed
          else
            authority.sub(/:\d+\z/, "")
          end

        Endpoint.new(raw: value, scheme: match[:scheme].downcase, host: host.downcase, source: source)
      end

      def resolved_endpoint(_root = Dir.pwd)
        from_environment = ENV.fetch("DOCKER_HOST", "").strip
        return parse_endpoint(from_environment, source: "DOCKER_HOST") unless from_environment.empty?

        named = ENV.fetch("DOCKER_CONTEXT", "").strip
        arguments = [ "context", "inspect", "--format", "{{.Endpoints.docker.Host}}" ]
        arguments << named unless named.empty?

        stdout, stderr, status = docker(*arguments)
        unless status.success?
          raise EndpointUnknown,
            "DOCKER_HOST is unset and the current Docker context could not be read " \
            "(#{stderr.strip.lines.first&.strip}). The destination is unknown, so it is not the lab."
        end

        parse_endpoint(stdout, source: named.empty? ? "the current docker context" : "docker context #{named}")
      end

      def claimable_endpoints(root = Dir.pwd)
        Array(config(root).dig("lab", "claimable_endpoints"))
      end

      # Loopback by resolution, not by spelling. `tcp://localhost.attacker.example`
      # starts with `tcp://localhost`, and prefix matching accepted it; so did
      # `tcp://127.0.0.1.example.com`. Both are somebody else's machine.
      def loopback?(host)
        addresses = Resolv.getaddresses(host)
        return false if addresses.empty?

        addresses.all? { |address| IPAddr.new(address).loopback? }
      rescue Resolv::ResolvError, IPAddr::Error, ArgumentError
        false
      end

      # Exact identity against the versioned allowlist. A scheme-only entry
      # (`unix`, `npipe`) is a socket on this machine and carries no host; a `tcp`
      # entry has to match the host exactly *and* resolve to loopback.
      def claimable_endpoint?(root = Dir.pwd, current = resolved_endpoint(root))
        claimable_endpoints(root).any? do |allowed|
          next false unless allowed.is_a?(Hash)
          next false unless allowed["scheme"].to_s.downcase == current.scheme

          expected = allowed["host"].to_s.downcase

          if expected.empty?
            current.host.empty?
          else
            current.host == expected && loopback?(current.host)
          end
        end
      end

      # The destination, judged before this process opens a connection to it.
      #
      # It used to be judged after `docker info` and the Engine version check, so
      # a foreign endpoint was contacted twice before the guardrail spoke — and
      # what it said, when that host was unreachable, was that the Engine version
      # was too old.
      def assert_claimable_endpoint!(root = Dir.pwd)
        current = resolved_endpoint(root)
        return current if claimable_endpoint?(root, current)

        raise NotTheLab, <<~MESSAGE.strip
          Refusing to create a Swarm on `#{current}`.

          The lab is created only on a local daemon. This endpoint is reached
          over the network, and a real Engine that has not joined a cluster yet
          looks exactly like an empty one from here — there is nothing left to
          tell them apart before `swarm init` has already run.

          The destination is the one the CLI would use: DOCKER_HOST when it is
          set, the current `docker context` otherwise. A tcp endpoint is claimable
          only when its host matches an allowed entry exactly and resolves to a
          loopback address.

          Point DOCKER_HOST at a disposable local daemon, or add the endpoint to
          `lab.claimable_endpoints` in config/architecture/docker-lab.yml, which
          needs the human review CODEOWNERS requires of that directory.
        MESSAGE
      end

      # Called before the mutation that *creates* the lab, where `assert_lab!`
      # cannot help: a daemon that has never been initialised carries no node
      # label, because a node label needs a Swarm. `up` was therefore the one
      # command that mutated an unidentified destination — it checked
      # `LocalNodeState`, refused an active swarm that was not ours, and ran
      # `swarm init` against anything inactive. A production Engine waiting to
      # join a cluster is exactly that.
      def assert_claimable!(root = Dir.pwd)
        assert_claimable_endpoint!(root)

        raise DockerUnavailable, "the Docker daemon is not reachable" unless available?

        # Already ours: `up` is idempotent.
        return true if lab_daemon?(root)

        state = JSON.parse(docker!("info", "--format", "{{json .Swarm}}"))["LocalNodeState"]
        return true if state == "inactive"

        raise NotTheLab, <<~MESSAGE.strip
          This daemon already runs a Swarm that is not the Opanel lab.

          It carries no `#{label(root)}=true` node label,
          so it may be a real cluster. Refusing to touch it.
          Point DOCKER_HOST at a disposable daemon.
        MESSAGE
      end

      # Called before every mutation of an existing lab. Fails closed, with the
      # reason.
      def assert_lab!(root = Dir.pwd)
        raise DockerUnavailable, "the Docker daemon is not reachable" unless available?

        return true if lab_daemon?(root)

        raise NotTheLab, <<~MESSAGE.strip
          This Docker daemon is not the Opanel lab.

          The lab is identified by the node label `#{label(root)}=true`, which
          `bin/swarm-lab up` applies. This daemon does not carry it, so it
          may be a real cluster — and the autonomous workspace may never
          touch one (Annex H §12.2).

          Run `bin/swarm-lab up` to create the lab, or point DOCKER_HOST at it.
          There is deliberately no environment variable that skips this check.
        MESSAGE
      end

      def labelled(kind, root = Dir.pwd)
        docker!(kind, "ls", "--filter", "label=#{label(root)}=true", "--format", "{{.Name}}")
          .split("\n").reject(&:empty?)
      end

      def lab_services(root = Dir.pwd)
        raise DockerUnavailable, "the Docker daemon is not reachable" unless available?

        labelled("service", root)
      end

      # Anything the harness created and did not clean up — after a crash, or a
      # killed test run. `reset` removes them; nothing may depend on inherited
      # state.
      #
      # **Every listing, or none.** A `docker … ls` that fails says nothing about
      # what is running; an empty list says there is nothing. These rescued the
      # first into the second, so `down` could walk past a failed enumeration into
      # `swarm leave` — after which the resources it never saw cannot be found at
      # all. Not knowing is now its own answer, and the callers refuse to act on it.
      def orphaned_resources(root = Dir.pwd)
        raise InventoryUnknown, "the Docker daemon is not reachable" unless available?

        prefix = resource_prefix(root)

        {
          "services" => labelled("service", root).select { |name| name.start_with?(prefix) },
          "networks" => labelled("network", root),
          "secrets" => labelled("secret", root),
          "configs" => labelled("config", root)
        }
      rescue DockerUnavailable => error
        raise InventoryUnknown,
          "the lab's contents could not be listed (#{error.message}) — " \
          "an enumeration that failed is not an empty lab"
      end

      def version_supported?(root = Dir.pwd)
        return false unless available?

        current = Gem::Version.new(docker!("info", "--format", "{{.ServerVersion}}").split("-").first)
        current >= Gem::Version.new(minimum_version(root))
      end
    end
  end
end
