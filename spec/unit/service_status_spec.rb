require "rails_helper"

RSpec.describe Opanel::ServiceStatus do
  describe ".derive" do
    subject(:derive) do
      described_class.derive(
        desired_revision: desired_revision,
        applied_revision: applied_revision,
        observation: observation,
        observed_at_timestamp: observed_at_timestamp
      )
    end

    let(:observed_at_timestamp) { Time.current }
    let(:observation) { nil }
    let(:desired_revision) { 1 }
    let(:applied_revision) { 1 }

    context "no observation yet" do
      it { expect(derive).to eq(Opanel::ServiceStatus::PENDING) }
    end

    context "observation exists but is stale" do
      let(:observation) { build_observation(observed_at: observed_at_timestamp - 400.seconds) }

      it { expect(derive).to eq(Opanel::ServiceStatus::FAILED) }

      it "does not declare HEALTHY even if tasks are healthy" do
        observation = build_observation(
          desired_tasks: 3,
          running_tasks: 3,
          healthy_tasks: 3,
          failed_tasks: 0,
          observed_at: observed_at_timestamp - 400.seconds
        )

        status = described_class.derive(
          desired_revision: 1,
          applied_revision: 1,
          observation: observation,
          observed_at_timestamp: observed_at_timestamp
        )

        expect(status).to eq(Opanel::ServiceStatus::FAILED)
      end
    end

    context "applied revision < desired revision" do
      let(:applied_revision) { nil }
      let(:observation) { build_observation }

      it { expect(derive).to eq(Opanel::ServiceStatus::DEPLOYING) }
    end

    context "applied revision = 0, desired revision = 1" do
      let(:applied_revision) { 0 }
      let(:observation) { build_observation }

      it { expect(derive).to eq(Opanel::ServiceStatus::DEPLOYING) }
    end

    context "applied revision = desired revision and all tasks healthy" do
      let(:observation) do
        build_observation(
          desired_tasks: 3,
          running_tasks: 3,
          healthy_tasks: 3,
          failed_tasks: 0
        )
      end

      it { expect(derive).to eq(Opanel::ServiceStatus::HEALTHY) }
    end

    context "applied revision = desired revision but not all tasks healthy" do
      context "fewer tasks running" do
        let(:observation) do
          build_observation(
            desired_tasks: 3,
            running_tasks: 2,
            healthy_tasks: 2,
            failed_tasks: 0
          )
        end

        it { expect(derive).to eq(Opanel::ServiceStatus::DEGRADED) }
      end

      context "failed tasks present" do
        let(:observation) do
          build_observation(
            desired_tasks: 3,
            running_tasks: 2,
            healthy_tasks: 2,
            failed_tasks: 1
          )
        end

        it { expect(derive).to eq(Opanel::ServiceStatus::DEGRADED) }
      end

      context "healthy count < running count (unhealthy running)" do
        let(:observation) do
          build_observation(
            desired_tasks: 3,
            running_tasks: 3,
            healthy_tasks: 2,
            failed_tasks: 0
          )
        end

        it { expect(derive).to eq(Opanel::ServiceStatus::DEGRADED) }
      end
    end

    context "observation is fresh (within threshold)" do
      let(:observation) { build_observation(observed_at: observed_at_timestamp - 100.seconds) }

      it "is not stale" do
        expect(described_class.stale?(observation, observed_at_timestamp)).to be false
      end
    end

    context "observation is at staleness boundary" do
      let(:observation) { build_observation(observed_at: observed_at_timestamp - 300.seconds) }

      it "is not stale (boundary is inclusive)" do
        # STALE_THRESHOLD = 300 seconds, so exactly 300 seconds old is NOT stale
        expect(described_class.stale?(observation, observed_at_timestamp)).to be false
      end
    end

    context "observation just beyond staleness threshold" do
      let(:observation) { build_observation(observed_at: observed_at_timestamp - 301.seconds) }

      it "is stale" do
        expect(described_class.stale?(observation, observed_at_timestamp)).to be true
      end
    end
  end

  describe ".stale?" do
    subject { described_class.stale?(observation, timestamp) }

    let(:timestamp) { Time.current }

    context "observation is nil" do
      let(:observation) { nil }

      it { is_expected.to be true }
    end

    context "observation is fresh" do
      let(:observation) { build_observation(observed_at: timestamp - 1.minute) }

      it { is_expected.to be false }
    end

    context "observation is old" do
      let(:observation) { build_observation(observed_at: timestamp - 6.minutes) }

      it { is_expected.to be true }
    end
  end

  private

  def build_observation(**kwargs)
    defaults = {
      desired_tasks: 1,
      running_tasks: 1,
      healthy_tasks: 1,
      failed_tasks: 0,
      observed_at: Time.current
    }

    ServiceObservation.new(defaults.merge(kwargs))
  end
end
