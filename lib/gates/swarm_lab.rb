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

      # Called before every mutation. Fails closed, with the reason.
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
