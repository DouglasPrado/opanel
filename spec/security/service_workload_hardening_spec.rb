require "rails_helper"

# M01-18 AC12 and AC3 — what a Service the platform creates is never given.
#
# Annex C §9 denies `privileged`, host mounts and the Docker socket to user
# workloads by default, and doc 08 keeps public exposure for the ingress in M04.
# The guarantee here is structural rather than a check: the executor's allowlist
# has no key for any of them, so there is no payload that could carry one. Both
# halves are asserted — the refusal at the boundary, and the spec the daemon
# actually ends up holding.
RSpec.describe "Service workload hardening", type: :security do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) do
    create(:service, environment: environment, team: team,
      image_ref: "docker.io/busybox:latest", image_digest: "sha256:#{'a' * 64}")
  end
  let(:network) do
    create(:network, environment: environment, team: team, cluster: environment.cluster,
      swarm_network_id: "abc123", status: Network::READY)
  end

  describe "the payload the reconciler builds" do
    let(:payload) { ServiceReconciler::SpecTranslation.payload_for(service, network: network) }

    it "carries no privilege, no mount, no socket and no published port" do
      serialized = JSON.generate(payload)

      expect(serialized).not_to include("Privileged")
      expect(serialized).not_to include("Mounts")
      expect(serialized).not_to include("docker.sock")
      expect(serialized).not_to include("PublishedPort")
      expect(payload).not_to have_key(:ports)
    end

    it "carries no environment values at all in M01" do
      expect(payload).not_to have_key(:env)
    end
  end

  describe "the executor's allowlist" do
    it "has no key through which a privilege, a mount or a port could be sent" do
      keys = SwarmExecutor::OPERATIONS.values.flatten.uniq

      expect(keys).not_to include("privileged", "mounts", "ports", "devices", "cap_add", "pid", "user")
    end

    it "refuses such a key before the daemon is reached" do
      # A strict double with nothing stubbed: any call to the Engine at all
      # fails the example, which is the assertion.
      client = instance_double(EngineClient)
      executor = SwarmExecutor.new(client: client)
      command = ExecutorCommand.new(id: "cmd_1", type: "create_service", cluster_id: "cl_1",
        resource_type: "Service", resource_id: service.external_id,
        payload: { image: "img", mounts: [ "/var/run/docker.sock:/var/run/docker.sock" ] })

      expect { executor.execute(command) }.to raise_error(ExecutorCommand::Invalid, /mounts/)
    end
  end

  describe "the Service the daemon ends up holding", :swarm, :integration, :service_lab do
    it "runs unprivileged, with no host mount, no socket and no published port" do
      reconcile

      container = swarm_service.dig("Spec", "TaskTemplate", "ContainerSpec")
      expect(container["Privileged"]).to be_nil
      expect(container["Mounts"]).to be_nil
      expect(JSON.generate(swarm_service["Spec"])).not_to include("docker.sock")
      expect(Array(swarm_service.dig("Endpoint", "Ports"))).to be_empty
      expect(Array(swarm_service.dig("Spec", "EndpointSpec", "Ports"))).to be_empty
    end
  end
end
