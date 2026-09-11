require "rails_helper"

# AC11 — the status is derived from an observation, never a stored claim of
# health — and the readiness view of doc 06 §14.1 that reads it.
RSpec.describe "the Cluster status", :integration do
  let(:team) { create(:team) }
  let(:actor) { team.owner }

  describe "the declared transitions" do
    it "allows PROVISIONING to reach either outcome of a bootstrap" do
      cluster = build(:cluster, status: Cluster::PROVISIONING)

      expect(cluster.can_transition_to?(Cluster::READY)).to be(true)
      expect(cluster.can_transition_to?(Cluster::DEGRADED)).to be(true)
    end

    it "allows a running cluster to move between READY, DEGRADED and UNREACHABLE" do
      expect(build(:cluster, status: Cluster::READY).can_transition_to?(Cluster::UNREACHABLE)).to be(true)
      expect(build(:cluster, status: Cluster::UNREACHABLE).can_transition_to?(Cluster::READY)).to be(true)
      expect(build(:cluster, status: Cluster::DEGRADED).can_transition_to?(Cluster::READY)).to be(true)
    end

    # Both terminal states have an empty edge list on purpose: entering
    # maintenance is an administrative operation nothing in M01 performs, and
    # leaving DELETING needs the runtime gone first (`M02-09`). An edge nothing
    # can traverse reads as a capability and can never be seen failing.
    it "declares no edge out of MAINTENANCE or DELETING" do
      expect(Cluster::TRANSITIONS.fetch(Cluster::MAINTENANCE)).to be_empty
      expect(Cluster::TRANSITIONS.fetch(Cluster::DELETING)).to be_empty
    end

    it "answers false for an unknown status rather than raising" do
      cluster = build(:cluster)
      cluster.status = "SOMETHING_ELSE"

      expect(cluster.can_transition_to?(Cluster::READY)).to be(false)
    end
  end

  # The database is what makes AC11 structural rather than a convention: a status
  # that is not PROVISIONING is an observation, and an observation with no
  # timestamp is a claim.
  describe "the database refuses a status with no observation" do
    it "rejects READY without observed_at" do
      expect {
        Cluster.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: team.id, name: "C", slug: "c",
          status: "READY", desired_revision: 1,
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /clusters_observed_status_has_a_timestamp/)
    end

    it "accepts PROVISIONING without one, because nothing has been observed yet" do
      expect { create(:cluster, team: team, status: "PROVISIONING", observed_at: nil) }
        .to change(Cluster, :count).by(1)
    end
  end

  describe "staleness" do
    it "treats a reading older than the window as stale" do
      expect(build(:cluster, :stale)).to be_observation_stale
    end

    it "treats a fresh reading as current" do
      expect(build(:cluster, :bootstrapped)).not_to be_observation_stale
    end

    # Never observed is not fresh. A Cluster nothing has looked at must not be
    # presented as one that was just checked.
    it "treats a Cluster nobody has observed as stale" do
      expect(build(:cluster, observed_at: nil)).to be_observation_stale
    end
  end

  describe ClusterReadinessView do
    def view(cluster) = described_class.call(actor: actor, cluster: cluster)

    it "reports a fresh READY cluster as operational" do
      expect(view(create(:cluster, :bootstrapped, team: team))).to be_operational
    end

    # The whole point of a derived status: an old reading is not evidence that
    # the cluster is working now.
    it "refuses to call a stale READY cluster operational" do
      result = view(create(:cluster, :stale, team: team))

      expect(result).to be_stale
      expect(result).not_to be_operational
    end

    it "refuses to call an unreachable cluster operational, and carries the cause" do
      result = view(create(:cluster, :unreachable, team: team))

      expect(result).not_to be_operational
      expect(result.unreachable_reason).to eq("DAEMON_UNREACHABLE")
    end

    # doc 06 §14.1's opening argument, made structural: a single-node cluster can
    # be operational without being highly available, and saying so is the point.
    it "never claims high availability for a single-node cluster" do
      expect(view(create(:cluster, :bootstrapped, team: team))).not_to be_highly_available
    end

    it "reports the observation as its own check, with the time" do
      cluster = create(:cluster, :bootstrapped, team: team)

      check = view(cluster).checks.find { |entry| entry.name == "observation" }

      expect(check.status).to eq(described_class::HEALTHY)
      expect(check.detail).to eq(cluster.observed_at.iso8601)
    end

    it "reports a cluster with no Swarm as unknown rather than as broken" do
      check = view(create(:cluster, team: team)).checks.find { |entry| entry.name == "swarm" }

      expect(check.status).to eq(described_class::UNKNOWN)
    end

    it "reads the permissions from ClusterPolicy" do
      cluster = create(:cluster, :bootstrapped, team: team)
      viewer = create(:user)
      create(:team_member, team: team, user: viewer, role: "VIEWER", status: "ACTIVE")

      result = described_class.call(actor: viewer, cluster: cluster)

      expect(result.permissions.refresh).to be(true)
      expect(result.permissions.bootstrap).to be(false)
    end
  end

  # AC7 from the refresh side, without a daemon: the cause is a named code and
  # the Cluster is not claimed healthy.
  describe RefreshClusterStatus do
    let(:cluster) { create(:cluster, :bootstrapped, team: team) }

    def executor_raising(code, message)
      Class.new do
        define_singleton_method(:code) { code }
        define_singleton_method(:message) { message }
        def self.info(**) = raise(SwarmBootstrap::EngineError.new(code, message))
      end
    end

    it "records UNREACHABLE with the classified cause when the daemon is absent" do
      described_class.call(actor: actor, cluster: cluster,
        executor: executor_raising(SwarmBootstrap::DAEMON_UNREACHABLE, "cannot connect"))

      expect(cluster.reload.status).to eq(Cluster::UNREACHABLE)
      expect(cluster.unreachable_reason).to eq(SwarmBootstrap::DAEMON_UNREACHABLE)
    end

    it "distinguishes a slow daemon from an absent one" do
      described_class.call(actor: actor, cluster: cluster,
        executor: executor_raising(SwarmBootstrap::DAEMON_TIMEOUT, "timed out after 20s"))

      expect(cluster.reload.unreachable_reason).to eq(SwarmBootstrap::DAEMON_TIMEOUT)
    end

    it "records when the reading was taken, even when it is bad news" do
      cluster.update!(observed_at: 1.hour.ago)

      described_class.call(actor: actor, cluster: cluster,
        executor: executor_raising(SwarmBootstrap::DAEMON_UNREACHABLE, "cannot connect"))

      expect(cluster.reload.observed_at).to be_within(5.seconds).of(Time.current)
    end

    # An unreachable daemon is a reading, not a request failure: the operator
    # asked what the state is and got an answer.
    it "succeeds, because the answer is the state" do
      result = described_class.call(actor: actor, cluster: cluster,
        executor: executor_raising(SwarmBootstrap::DAEMON_UNREACHABLE, "cannot connect"))

      expect(result).to be_success
    end

    # NOT_FOUND rather than FORBIDDEN: across Teams the two must be
    # indistinguishable (Annex C §7.3).
    it "answers somebody from another Team as if the cluster were absent" do
      result = described_class.call(actor: create(:team).owner, cluster: cluster,
        executor: executor_raising(SwarmBootstrap::DAEMON_UNREACHABLE, "x"))

      expect(result).to be_failure
      expect(result.code).to eq("NOT_FOUND")
      expect(cluster.reload.status).to eq(Cluster::READY)
    end
  end
end
