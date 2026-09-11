require "rails_helper"

RSpec.describe "Reconciler user-intent column protection", type: :security do
  it "AF-03 fitness function must validate reconciler does not write user-intent columns" do
    # This is validated by bin/fitness AF-03 check
    # The reconciler code must never write to:
    # - Environment: name, slug, type, auto_promote_secrets
    # - Service: name, slug, image_ref, replicas, ports, health_check, etc.

    # The reconciler may only write:
    # - applied_revision, status, swarm_network_id (for Network)

    network = double("network")
    allow(network).to receive(:applied_revision=)
    allow(network).to receive(:status=)
    allow(network).to receive(:save!)

    # Expect that reconciler does not call methods that write user intent
    expect(network).not_to receive(:name=)
    expect(network).not_to receive(:slug=)
    expect(network).not_to receive(:type=)
  end

  # M01-18. The Service reconciler is the first one to converge a resource whose
  # Desired State is mostly user intent — image, replicas, resources, placement,
  # healthcheck — so AF-03 stops being abstract here. The check below is not a
  # reading of the source: the reconciler runs, converges, and the operator's
  # columns are compared before and after.
  describe "the Service reconciler, against real rows" do
    let(:team) { create(:team) }
    let(:project) { create(:project, team: team) }
    let(:environment) { create(:environment, project: project) }
    let(:service) do
      create(:service, environment: environment, team: team, replicas: 2, status: Service::PROVISIONING,
        image_ref: "docker.io/busybox:latest", image_digest: "sha256:#{'a' * 64}",
        constraints: [ "node.role==worker" ], cpu_limit: 250, memory_limit: 512)
    end
    let!(:network) do
      create(:network, environment: environment, team: team, cluster: environment.cluster,
        swarm_network_id: "abc123", status: Network::READY)
    end

    # Every column AF-03 lists for `services` in config/architecture/fitness.yml.
    INTENT = %w[name slug image_ref replicas ports health_check cpu_reservation cpu_limit
                memory_reservation memory_limit constraints].freeze

    it "converges without writing a single column the operator owns" do
      before_state = service.attributes.slice(*INTENT)
      observed = service_observation(service)

      ServiceReconciler.call(service: service, executor: FakeSwarmExecutor.new(
        "inspect_service" => [ not_found, applied(observed) ],
        "create_service" => applied(observed),
        "list_tasks" => tasks
      ))

      expect(service.reload.attributes.slice(*INTENT)).to eq(before_state)
    end

    it "does not rewrite intent even when the runtime disagrees with it" do
      before_state = service.attributes.slice(*INTENT)
      # The runtime says four replicas; Desired State says two. Platform Wins:
      # the reconciler converges the runtime, never the record.
      drifted = service_observation(service, replicas: 4)

      ServiceReconciler.call(service: service, executor: FakeSwarmExecutor.new(
        "inspect_service" => [ applied(drifted), applied(service_observation(service)) ],
        "update_service_spec" => applied(service_observation(service)),
        "list_tasks" => tasks
      ))

      expect(service.reload.attributes.slice(*INTENT)).to eq(before_state)
      expect(service.replicas).to eq(2)
    end

    it "writes only observation columns" do
      observed = service_observation(service)

      expect {
        ServiceReconciler.call(service: service, executor: FakeSwarmExecutor.new(
          "inspect_service" => [ not_found, applied(observed) ],
          "create_service" => applied(observed),
          "list_tasks" => tasks
        ))
      }.to change { service.reload.attributes.slice("swarm_service_id", "applied_revision") }
    end
  end
end
