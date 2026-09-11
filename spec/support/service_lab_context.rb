# The setup every M01-18 lab example needs: a Service whose Desired State can
# actually converge on the lab Engine.
#
# Two things make that non-trivial and both are deliberate.
#
# **The image is pinned to a digest** (AC2), and the digest is the one the lab
# node already holds. `config/architecture/docker-lab.yml` says the lab is
# usable without registry access on purpose, so the reference is built from the
# local `RepoDigests` entry and nothing is ever pulled.
#
# **The overlay network is real.** The Service attaches to the Environment's
# network by the runtime id the network reconciler would have recorded (AC3), so
# the row is created here pointing at a network that exists on the daemon.
RSpec.shared_context "a Service the reconciler can converge" do
  # PostgreSQL's `now()` is the **transaction start** time, and
  # `use_transactional_fixtures` wraps the whole example in one transaction —
  # so inside an example the database clock does not move while the real one
  # does. `AcquireResourceLock` compares a lease written from Ruby's clock
  # (`Time.current`) against the database's `now()`, so after a pass that spent
  # three seconds talking to the Engine, the lease it released still looks held
  # to the next pass and no second pass can ever acquire it.
  #
  # That is an artifact of the harness, not of the lease: in production nothing
  # holds a transaction open across a reconcile, and `now()` advances with every
  # statement. Pinning Ruby's clock to the same instant the transaction started
  # removes the artifact without touching the lease, which belongs to M01-15 and
  # to no boundary of this Story. The mixed-clock arithmetic itself is recorded
  # in the Story report as inherited debt.
  before { travel_to(Time.current) }

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }

  # `busybox@sha256:…`, read from the node. Skips rather than lies when the
  # local image carries no digest (a locally built image has none).
  let(:lab_digest) do
    digests = Opanel::Gates::SwarmLab.docker!("image", "inspect", lab_image,
      "--format", "{{json .RepoDigests}}")
    reference = JSON.parse(digests).first
    skip "the lab image #{lab_image} carries no registry digest; AC2 cannot be proved from it" if reference.nil?

    reference.split("@").last
  end

  # Unique per example, not merely per run: `lab_name`'s counter restarts with
  # each example, and a network that outlives a failed example would otherwise
  # collide with the next one and hide the failure that caused it.
  let(:lab_network_name) { "#{lab_name('net')}-#{SecureRandom.hex(3)}" }

  let(:lab_network_id) do
    Opanel::Gates::SwarmLab.docker!("network", "create", "--driver", "overlay",
      "--label", "#{lab_label}=true", lab_network_name)
    created_resources << [ "network", lab_network_name ]
    Opanel::Gates::SwarmLab.docker!("network", "inspect", lab_network_name, "--format", "{{.Id}}").strip
  end

  let!(:network) do
    create(:network, environment: environment, team: team, cluster: environment.cluster,
      name: lab_network_name, swarm_network_id: lab_network_id, status: Network::READY,
      applied_revision: 1)
  end

  let(:service) do
    create(:service, environment: environment, team: team, replicas: 1,
      status: Service::PROVISIONING, command: "sleep 3600",
      image_ref: lab_image, image_digest: lab_digest).tap do |record|
        # Whatever the example does, the Swarm Service goes away with it.
        created_resources << [ "service", record.technical_name ]
      end
  end

  # A network cannot be removed while a Service is attached to it, and the
  # harness's cleanup walks its list in order — so the Service goes first, here,
  # before the shared `after` hook reaches the network.
  after do
    created_resources.select { |kind, _| kind == "service" }
      .each { |kind, name| Opanel::Gates::SwarmLab.remove(kind, name) }
    created_resources.reject! { |kind, _| kind == "service" }
  end

  def reconcile(subject_service = service, **options)
    ServiceReconciler.call(service: subject_service, **options)
  end

  # What the daemon actually holds, read through the CLI rather than through the
  # code under test.
  def swarm_service(name = service.technical_name)
    JSON.parse(Opanel::Gates::SwarmLab.docker!("service", "inspect", name)).first
  end

  def swarm_service_exists?(name = service.technical_name)
    Opanel::Gates::SwarmLab.docker!("service", "ls", "--filter", "name=#{name}", "--format", "{{.Name}}")
      .split("\n").include?(name)
  end

  def swarm_services_named(name = service.technical_name)
    Opanel::Gates::SwarmLab.docker!("service", "ls", "--filter", "name=#{name}", "--format", "{{.Name}}")
      .split("\n").count { |line| line == name }
  end
end

RSpec.configure do |config|
  config.include_context "a Service the reconciler can converge", :service_lab
end
