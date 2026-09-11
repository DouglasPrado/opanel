require "rails_helper"

# The executor against a **real** Engine, in the disposable lab (Annex D §7).
#
# Everything the Engine cannot be asked to do on demand is in
# `spec/unit/swarm_executor_spec.rb`. What is here is what only a daemon can
# answer: that the specs it accepts are the ones the executor builds, that a
# stale version really is refused, that a removed service really is gone, and
# what `Version.Index` looks like when it moves.
#
# Every resource carries the lab label and is registered for cleanup, so a
# failing example leaves nothing behind for the next run to inherit.
RSpec.describe "the Swarm Executor, against a real Engine", :swarm, :integration do
  subject(:executor) { SwarmExecutor.new }

  let(:resource_id) { "svc_#{Opanel::Identifier.generate}" }
  let(:service_name) { lab_name("exec") }

  def command(type, id: resource_id, resource_type: "Service", **payload)
    ExecutorCommand.new(id: "cmd_#{type}_#{SecureRandom.hex(3)}", type: type, cluster_id: "cl_lab",
      resource_type: resource_type, resource_id: id, correlation_id: "corr_lab", payload: payload)
  end

  def create_service(**extra)
    created_resources << [ "service", service_name ]
    # Build ownership labels for the test service.
    # For adoption testing (AC7), the second create must pass the same labels
    # so find_by_label can locate the existing resource.
    labels = {
      lab_label => "true",
      # Ownership labels: at minimum, service_id to identify the resource.
      "com.opanel.service_id" => resource_id
    }
    executor.execute(command("create_service", name: service_name, image: lab_image,
      command: %w[sleep 3600], replicas: 1, labels: labels, **extra))
  end

  describe "a service, end to end (AC4, AC5, AC7, AC8)" do
    it "creates, observes the version, updates with CAS, refuses a stale version, and removes" do
      created = create_service
      expect(created).to be_applied
      expect(created.runtime_resource_ids.length).to eq(1)
      expect(created.observed_runtime_version).to be_a(Integer)
      engine_id = created.runtime_resource_ids.first

      inspected = executor.execute(command("inspect_service", id: resource_id))
      expect(inspected).to be_applied
      # ADR-0009 §2: the name is on the observation, not in the metadata bag.
      expect(inspected.observed.name).to eq(service_name)
      version = inspected.observed_runtime_version

      # The revision applied with the version just observed: accepted, and the
      # observed version moves.
      updated = executor.execute(command("update_service_spec", id: resource_id, replicas: 2, version: version))
      expect(updated).to be_applied
      expect(updated.observed_runtime_version).to be > version

      # The same revision applied with the version that is now stale: CONFLICT,
      # and the runtime is untouched. This is the case the CLI could never give.
      stale = executor.execute(command("update_service_spec", id: resource_id, replicas: 3, version: version))
      expect(stale).to be_conflict
      expect(executor.execute(command("inspect_service", id: resource_id)).observed_runtime_version)
        .to eq(updated.observed_runtime_version)

      removed = executor.execute(command("remove_service", id: resource_id))
      expect(removed).to be_applied

      # AC8 — already gone is converged.
      again = executor.execute(command("remove_service", id: resource_id))
      expect(again).to be_noop
      expect(again.safe_metadata[:absent]).to be(true)
    end

    # AC7 — the second create finds the first by label and adopts it.
    it "adopts a service that already carries its label rather than creating a second" do
      first = create_service
      expect(first).to be_applied

      second = executor.execute(command("create_service", name: "#{service_name}-again", image: lab_image,
        labels: { lab_label => "true" }))

      expect(second).to be_noop
      expect(second.safe_metadata[:adopted]).to be(true)
      expect(second.runtime_resource_ids).to eq(first.runtime_resource_ids)
    end

    it "lists the service's tasks with their states" do
      created = create_service

      tasks = executor.execute(command("list_tasks", id: resource_id))

      expect(tasks).to be_applied
      expect(tasks.safe_metadata[:count]).to be >= 1
      expect(tasks.safe_metadata[:states]).to be_a(Hash)
    end

    it "reads the service's logs, bounded" do
      created = create_service(command: [ "sh", "-c", "echo hello-from-lab; sleep 3600" ])

      lines = nil
      10.times do
        result = executor.execute(command("service_logs", id: resource_id, tail: 5))
        lines = result.safe_metadata[:lines]
        break if lines&.any? { |l| l.include?("hello-from-lab") }

        sleep 1
      end

      expect(lines).to include(a_string_including("hello-from-lab"))
    end
  end

  describe "a network" do
    let(:environment_id) { "env_#{Opanel::Identifier.generate}" }
    let(:network_name) { lab_name("net") }

    it "creates, inspects, adopts on a second create, and removes idempotently" do
      created_resources << [ "network", network_name ]

      # Build ownership labels for the test network.
      # For adoption testing (AC7), the second create must pass the same labels
      # so find_by_label can locate the existing network.
      labels = {
        lab_label => "true",
        # Ownership labels: at minimum, environment_id to identify the network.
        # ADR-0009 §5: external form env_<environmentId>
        "com.opanel.environment_id" => environment_id
      }

      created = executor.execute(command("create_network", id: environment_id, resource_type: "Network",
        name: network_name, labels: labels))
      expect(created).to be_applied

      inspected = executor.execute(command("inspect_network", id: environment_id,
resource_type: "Network"))
      expect(inspected).to be_applied
      # ADR-0009 §2: driver is in observed.attributes, under the network allowlist.
      expect(inspected.observed.attributes["driver"]).to eq("overlay")

      adopted = executor.execute(command("create_network", id: environment_id, resource_type: "Network",
        name: "#{network_name}-again", labels: labels))
      expect(adopted).to be_noop

      expect(executor.execute(command("remove_network", id: environment_id,
resource_type: "Network"))).to be_applied
      expect(executor.execute(command("remove_network", id: environment_id,
resource_type: "Network"))).to be_noop
    end
  end

  describe "nodes" do
    it "lists the lab's one manager and inspects it with its version" do
      listed = executor.execute(command("list_nodes", id: "self", resource_type: "Cluster"))
      expect(listed).to be_applied
      expect(listed.safe_metadata[:managers]).to eq(1)

      node = executor.execute(command("inspect_node", id: listed.runtime_resource_ids.first, resource_type: "Node"))
      expect(node).to be_applied
      # ADR-0009 §2: role is in observed.attributes, under the node allowlist.
      expect(node.observed.attributes["role"]).to eq("manager")
      expect(node.observed_runtime_version).to be_a(Integer)
    end
  end

  # AC9, from the only side a real single-node lab can show: it *is* a manager,
  # so the guard lets it through — the refusal itself is proved with a stood-in
  # worker in the unit spec.
  it "runs, because the lab node is a manager" do
    expect(SwarmBootstrap.info.manager?).to be(true)
    expect(executor.execute(command("list_nodes", id: "self", resource_type: "Cluster"))).to be_applied
  end
end
