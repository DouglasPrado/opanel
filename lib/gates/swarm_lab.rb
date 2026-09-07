# frozen_string_literal: true

require "json"
require "open3"
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

      Status = Struct.new(:available, :swarm_state, :is_lab, :engine_version, :api_version,
        :node_count, :services, :orphans, :reason, keyword_init: true) do
        def available? = available
        def lab? = is_lab
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

        Status.new(
          available: true,
          swarm_state: swarm_state,
          is_lab: lab_daemon?(root),
          engine_version: info["ServerVersion"],
          api_version: version.dig("Server", "ApiVersion"),
          node_count: info.dig("Swarm", "Nodes"),
          services: lab_services(root),
          orphans: orphaned_resources(root)
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

      # The endpoint this process would talk to, normalised.
      def endpoint = ENV.fetch("DOCKER_HOST", "").strip

      def claimable_endpoints(root = Dir.pwd)
        Array(config(root).dig("lab", "claimable_endpoints"))
      end

      def claimable_endpoint?(root = Dir.pwd)
        current = endpoint

        claimable_endpoints(root).any? do |allowed|
          allowed.to_s.empty? ? current.empty? : current.start_with?(allowed.to_s)
        end
      end

      # Called before the mutation that *creates* the lab, where `assert_lab!`
      # cannot help: a daemon that has never been initialised carries no node
      # label, because a node label needs a Swarm. `up` was therefore the one
      # command that mutated an unidentified destination — it checked
      # `LocalNodeState`, refused an active swarm that was not ours, and ran
      # `swarm init` against anything inactive. A production Engine waiting to
      # join a cluster is exactly that.
      def assert_claimable!(root = Dir.pwd)
        raise DockerUnavailable, "the Docker daemon is not reachable" unless available?

        # Already ours: `up` is idempotent.
        return true if lab_daemon?(root)

        unless claimable_endpoint?(root)
          raise NotTheLab, <<~MESSAGE.strip
            Refusing to create a Swarm on `#{endpoint}`.

            The lab is created only on a local daemon. This endpoint is reached
            over the network, and a real Engine that has not joined a cluster yet
            looks exactly like an empty one from here — there is nothing left to
            tell them apart before `swarm init` has already run.

            Point DOCKER_HOST at a disposable local daemon, or add the endpoint to
            `lab.claimable_endpoints` in config/architecture/docker-lab.yml, which
            needs the human review CODEOWNERS requires of that directory.
          MESSAGE
        end

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

      def lab_services(root = Dir.pwd)
        return [] unless available?

        docker!("service", "ls", "--filter", "label=#{label(root)}=true", "--format", "{{.Name}}")
          .split("\n").reject(&:empty?)
      rescue DockerUnavailable
        []
      end

      # Anything the harness created and did not clean up — after a crash, or a
      # killed test run. `reset` removes them; nothing may depend on inherited
      # state.
      def orphaned_resources(root = Dir.pwd)
        return {} unless available?

        prefix = resource_prefix(root)

        {
          "services" => lab_services(root).select { |name| name.start_with?(prefix) },
          "networks" => docker!("network", "ls", "--filter", "label=#{label(root)}=true",
            "--format", "{{.Name}}").split("\n").reject(&:empty?),
          "secrets" => docker!("secret", "ls", "--filter", "label=#{label(root)}=true",
            "--format", "{{.Name}}").split("\n").reject(&:empty?),
          "configs" => docker!("config", "ls", "--filter", "label=#{label(root)}=true",
            "--format", "{{.Name}}").split("\n").reject(&:empty?)
        }
      rescue DockerUnavailable
        {}
      end

      def version_supported?(root = Dir.pwd)
        return false unless available?

        current = Gem::Version.new(docker!("info", "--format", "{{.ServerVersion}}").split("-").first)
        current >= Gem::Version.new(minimum_version(root))
      end
    end
  end
end
