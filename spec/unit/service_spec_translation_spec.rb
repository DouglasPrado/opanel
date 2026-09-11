require "rails_helper"

# M01-18 §4 — Desired State becomes a Swarm Service Spec.
#
# The translation is where AC2, AC3 and AC12 are decided: an image is pinned to
# a digest or the Service is not deployed; the Environment's overlay is the only
# network; and no published port, mount, privilege or socket has a path into the
# payload at all.
RSpec.describe ServiceReconciler::SpecTranslation, type: :unit do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:digest) { "sha256:#{'a' * 64}" }
  let(:service) do
    create(:service, environment: environment, replicas: 3,
      image_ref: "docker.io/busybox:latest", image_digest: digest)
  end
  let(:network) do
    create(:network, environment: environment, team: team, cluster: environment.cluster,
      swarm_network_id: "abc123", status: Network::READY)
  end

  def payload = described_class.payload_for(service, network: network)

  describe "the image (AC2)" do
    it "references the digest, not the tag" do
      expect(described_class.image_for(service)).to eq("docker.io/busybox@#{digest}")
      expect(payload[:image]).to eq("docker.io/busybox@#{digest}")
    end

    it "keeps the digest when the operator pinned one in the reference itself" do
      service.update_columns(image_ref: "docker.io/busybox@#{digest}")

      expect(described_class.image_for(service)).to eq("docker.io/busybox@#{digest}")
    end

    it "answers nil when nothing pins the image, so the diff can refuse to deploy it" do
      service.update_columns(image_digest: nil, image_ref: "docker.io/busybox:latest")

      expect(described_class.image_for(service)).to be_nil
    end

    it "answers nil rather than raising when the reference does not parse" do
      service.update_columns(image_ref: "not a reference", image_digest: digest)

      expect(described_class.image_for(service)).to be_nil
    end
  end

  describe "the network (AC3)" do
    it "attaches the Environment's overlay by its runtime id and nothing else" do
      expect(payload[:networks]).to eq([ "abc123" ])
    end

    it "publishes no port: exposure exists from M04, through the ingress" do
      expect(payload).not_to have_key(:ports)
      expect(payload.to_s).not_to include("PublishedPort")
    end
  end

  describe "the workload (AC12)" do
    it "grants no privilege, mounts no host path and passes no docker socket" do
      expect(payload).not_to have_key(:privileged)
      expect(payload).not_to have_key(:mounts)
      expect(payload.to_s).not_to include("docker.sock")
      expect(payload.to_s).not_to include("/var/run")
    end

    it "sends no environment variables: sensitive values are the Vault's, in M03" do
      expect(payload[:env]).to be_nil
    end
  end

  describe "replicas, command and args" do
    it "carries the desired replica count" do
      expect(payload[:replicas]).to eq(3)
    end

    it "splits a command into the argv the Engine expects" do
      service.update_columns(command: "sleep 3600")

      expect(payload[:command]).to eq(%w[sleep 3600])
    end

    it "omits a command that was never set" do
      expect(payload).not_to have_key(:command)
    end
  end

  # The columns are bigint and the unit is documented nowhere: doc 03 §5.1
  # speaks in CPUs and MiB, the factory writes 100/200 and 256/512. The reading
  # below is millicores and MiB, named in constants so it is one line to change
  # and one line to review. A wrong reading here is a 1000x resource error.
  describe "resources" do
    it "converts millicores to nanocpus and MiB to bytes" do
      service.update_columns(cpu_reservation: 100, cpu_limit: 250,
        memory_reservation: 256, memory_limit: 512)

      expect(payload[:resources]).to eq(
        "cpu_reservation_nano" => 100 * 1_000_000,
        "cpu_limit_nano" => 250 * 1_000_000,
        "memory_reservation_bytes" => 256 * 1_048_576,
        "memory_limit_bytes" => 512 * 1_048_576
      )
    end

    it "omits resources entirely when none are set" do
      expect(payload).not_to have_key(:resources)
    end
  end

  describe "placement and healthcheck" do
    it "carries placement constraints as the Engine's strings" do
      service.update_columns(constraints: [ "node.role==worker" ])

      expect(payload[:placement]).to eq([ "node.role==worker" ])
    end

    it "carries a healthcheck when the Service declares one" do
      service.update_columns(health_check: { "test" => [ "CMD", "true" ], "interval_seconds" => 10 })

      expect(payload[:healthcheck]["Test"]).to eq([ "CMD", "true" ])
      expect(payload[:healthcheck]["Interval"]).to eq(10_000_000_000)
    end

    it "omits a healthcheck the Service does not declare" do
      expect(payload).not_to have_key(:healthcheck)
    end
  end

  describe "the update policy" do
    it "is conservative and fixed: pause on failure, never an automatic rollback" do
      # Rollout health verification and automatic rollback are M06-04..M06-06.
      expect(payload[:update_config]["FailureAction"]).to eq("pause")
      expect(payload[:update_config]["Parallelism"]).to eq(1)
    end
  end

  describe "ownership" do
    it "carries the labels that make the resource reconcilable, and the derived name" do
      expect(payload[:name]).to eq(service.technical_name)
      expect(payload[:labels]).to include(
        "com.opanel.managed" => "true",
        "com.opanel.service_id" => service.external_id,
        "com.opanel.desired_revision" => service.desired_revision.to_s
      )
    end

    it "keeps the name inside the Engine's 63-character limit" do
      expect(payload[:name].length).to be <= 63
    end
  end

  describe "as an executor payload" do
    it "carries only keys the executor's allowlist declares" do
      service.update_columns(command: "sleep 3600", cpu_limit: 250, constraints: [ "node.role==worker" ])
      allowed = SwarmExecutor::OPERATIONS.fetch("create_service")

      expect(payload.keys.map(&:to_s) - allowed).to be_empty
    end

    it "survives ExecutorCommand's secret screen" do
      command = ExecutorCommand.new(id: "cmd_1", type: "create_service", cluster_id: environment.cluster.id,
        resource_type: "Service", resource_id: service.external_id, payload: payload)

      expect { command.validate!(SwarmExecutor::OPERATIONS.fetch("create_service")) }.not_to raise_error
    end
  end
end
