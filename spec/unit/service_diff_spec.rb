require "rails_helper"

# M01-18. The diff is a pure function over desired state and one observation
# (doc 07 §11.4). Every class it declares must be reachable from real input:
# `lib/opanel/network_diff.rb:53-58` shipped a BLOCKED branch that could only
# fire at create time, and the ledger told this Story not to repeat that shape.
# So there is an example per class here, and each one names what decides it.
#
# DELETE is M02-09 and DRIFT is M02-06. Neither is implemented, so neither is
# a constant in `Opanel::ServiceDiff`.
RSpec.describe Opanel::ServiceDiff, type: :unit do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:cluster) { environment.cluster }
  let(:service) do
    create(:service, environment: environment, replicas: 2,
      image_ref: "docker.io/busybox:latest",
      image_digest: "sha256:#{'a' * 64}")
  end
  let(:network) do
    create(:network, environment: environment, team: team, cluster: cluster,
      swarm_network_id: "abc123", status: Network::READY)
  end
  let(:desired_image) { "docker.io/busybox@sha256:#{'a' * 64}" }

  # An observation as the executor would normalize it (ADR-0009 §2/§3): the
  # service allowlist carries image, replicas and mode, and nothing else.
  def observation(image: desired_image, replicas: 2, labels: nil, revision: service.desired_revision)
    Opanel::RuntimeObservation.new(
      kind: "service",
      runtime_id: "runtime1",
      name: service.technical_name,
      labels: labels || Opanel::Ownership.labels_for(service).merge(
        "com.opanel.desired_revision" => revision.to_s
      ),
      version: 12,
      attributes: { "image" => image, "replicas" => replicas, "mode" => "Replicated" }
    )
  end

  def compute(actual:, image: desired_image, net: network)
    described_class.compute(service: service, desired_image: image, network: net, actual: actual)
  end

  describe "CREATE" do
    it "is decided by the absence of any resource carrying our ownership label" do
      diff = compute(actual: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::CREATE)
      expect(diff.actions_to_apply).to eq([ { action: "create", name: service.technical_name } ])
      expect(diff.error_reason).to be_nil
    end
  end

  describe "NOOP" do
    it "is decided by an owned resource whose image, replicas and revision all agree" do
      diff = compute(actual: observation)

      expect(diff.diff_class).to eq(ReconciliationRun::NOOP)
      expect(diff.actions_to_apply).to be_empty
    end
  end

  describe "UPDATE_SAFE" do
    it "is decided by a replica count that differs while the image holds — a scale replaces no task" do
      diff = compute(actual: observation(replicas: 5))

      expect(diff.diff_class).to eq(ReconciliationRun::UPDATE_SAFE)
      expect(diff.actions_to_apply.first[:action]).to eq("update")
    end
  end

  describe "ROLLOUT" do
    it "is decided by an image that differs — every task is replaced" do
      diff = compute(actual: observation(image: "docker.io/busybox@sha256:#{'b' * 64}"))

      expect(diff.diff_class).to eq(ReconciliationRun::ROLLOUT)
    end

    it "is decided by a revision that moved while image and replicas agree" do
      # The observation's allowlist carries image, replicas and mode only, so a
      # change to args, env, resources, placement or healthcheck is invisible in
      # it. The ownership label carries the revision, and the safe reading of an
      # unseen spec change is the task-replacing class, never NOOP.
      diff = compute(actual: observation(revision: service.desired_revision - 1))

      expect(diff.diff_class).to eq(ReconciliationRun::ROLLOUT)
    end
  end

  describe "BLOCKED" do
    it "is decided by an image that is not pinned to a digest (AC2)" do
      service.update_columns(image_digest: nil)
      diff = compute(actual: nil, image: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to match(/digest/i)
    end

    it "is decided by an Environment network that cannot be attached (AC3)" do
      diff = compute(actual: nil, net: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to match(/network/i)
    end

    it "is decided by a network that exists but has not converged" do
      network.update!(status: Network::PROVISIONING, swarm_network_id: nil)
      diff = compute(actual: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to match(/network/i)
    end

    it "is decided by a resource carrying our label whose ownership does not resolve — never adopted" do
      foreign = observation(labels: {
        "com.opanel.managed" => "true",
        "com.opanel.service_id" => service.external_id
        # team_id, project_id and environment_id absent: the predicate answers false
      })

      diff = compute(actual: foreign)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to match(/not managed by the platform/i)
    end

    it "is decided by a placement constraint that is not a constraint" do
      service.update_columns(constraints: [ "node.role==worker; rm -rf /" ])
      diff = compute(actual: nil)

      expect(diff.diff_class).to eq(ReconciliationRun::BLOCKED_CLASS)
      expect(diff.error_reason).to match(/placement/i)
    end
  end

  describe "as a pure function" do
    it "writes nothing and calls nothing on the Docker boundary" do
      expect(SwarmExecutor).not_to receive(:new)

      expect { compute(actual: observation(replicas: 9)) }
        .not_to change { service.reload.attributes }
    end

    it "declares only the classes M01-18 implements" do
      # DELETE (M02-09) and DRIFT (M02-06) are absent on purpose: a diff class
      # that no input can produce is the defect this file exists to avoid.
      expect(described_class.constants.map(&:to_s)).to match_array(
        %w[NOOP CREATE UPDATE_SAFE ROLLOUT BLOCKED CONSTRAINT_FORMAT]
      )
    end
  end
end
