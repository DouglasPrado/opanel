require "rails_helper"

# The harness itself, checked against real PostgreSQL.
#
# A concurrency helper nobody proved can expose a race is a helper that gives
# false confidence: every test using it would pass whether or not the code under
# test was correct. So the barrier is shown to *reproduce* a lost update first,
# and only then to prevent one.
RSpec.describe "backend test harness", type: :integration do
  describe "real PostgreSQL" do
    it "runs against PostgreSQL, not SQLite" do
      expect(ActiveRecord::Base.connection.adapter_name).to eq("PostgreSQL")
    end

    it "runs in the test database, which is not development or ci" do
      current = ActiveRecord::Base.connection_db_config.database
      others = %w[development ci production].map do |environment|
        ActiveRecord::Base.configurations.configs_for(env_name: environment, name: "primary").database
      end

      expect(others).not_to include(current)
    end
  end

  describe "random order" do
    it "shuffles by default and reports the seed so a failure is reproducible" do
      global_ordering = RSpec.configuration.ordering_registry.fetch(:global)

      expect(global_ordering).to be_a(RSpec::Core::Ordering::Random)
      expect(RSpec.configuration.seed).to be_a(Integer)
    end
  end

  describe "clock control" do
    it "freezes time" do
      frozen = Time.zone.parse("2026-01-01 12:00:00 UTC")

      travel_to(frozen) do
        expect(Time.current).to eq(frozen)
        expect(Time.current).to eq(frozen)
      end
    end

    it "exercises an expiry without waiting for it" do
      lease_granted_at = Time.current
      lease_ttl = 30.minutes
      expired = -> { Time.current > lease_granted_at + lease_ttl }

      expect(expired.call).to be(false)

      travel(31.minutes)

      expect(expired.call).to be(true), "the lease should have expired without the suite sleeping for it"
    end

    it "restores the clock between examples" do
      expect(Time.current).to be_within(5.seconds).of(Time.now)
    end
  end

  describe "unique namespaces" do
    it "never repeats a name inside one example" do
      names = Array.new(5) { unique_namespace }

      expect(names.uniq.length).to eq(5)
    end

    it "carries the parallel worker number so two workers cannot collide" do
      expect(unique_namespace).to include(ENV.fetch("TEST_ENV_NUMBER", "0").presence || "0")
      expect(unique_namespace).to include(Process.pid.to_s)
    end

    it "accepts a prefix so a leaked resource says what created it" do
      expect(unique_namespace("swarm-service")).to start_with("swarm-service-")
    end
  end

  describe "concurrency barrier", :concurrent do
    let(:checkpoint_name) { unique_namespace("lost-update") }

    after { InfrastructureCheckpoint.where(name: checkpoint_name).delete_all }

    it "reproduces a lost update when two writers read before either writes" do
      checkpoint = InfrastructureCheckpoint.create!(name: checkpoint_name, counter: 0)
      both_have_read = barrier(2)

      concurrently(
        -> {
          value = InfrastructureCheckpoint.find(checkpoint.id).counter
          both_have_read.wait
          InfrastructureCheckpoint.where(id: checkpoint.id).update_all(counter: value + 1)
        },
        -> {
          value = InfrastructureCheckpoint.find(checkpoint.id).counter
          both_have_read.wait
          InfrastructureCheckpoint.where(id: checkpoint.id).update_all(counter: value + 1)
        }
      )

      expect(checkpoint.reload.counter).to eq(1),
        "the barrier did not force the interleaving: without it this race is invisible"
    end

    it "prevents the same lost update when the row is locked" do
      checkpoint = InfrastructureCheckpoint.create!(name: checkpoint_name, counter: 0)
      both_started = barrier(2)

      increment = lambda do
        both_started.wait
        InfrastructureCheckpoint.transaction do
          locked = InfrastructureCheckpoint.lock.find(checkpoint.id)
          locked.update!(counter: locked.counter + 1)
        end
      end

      concurrently(increment, increment)

      expect(checkpoint.reload.counter).to eq(2), "SELECT ... FOR UPDATE should have serialized the writers"
    end

    it "fails loudly instead of hanging when a participant never arrives" do
      lonely = barrier(2, timeout: 0.5)

      expect { lonely.wait }.to raise_error(ConcurrencyHelpers::Timeout, /1\/2 arrived/)
    end

    it "re-raises a failure from inside a thread" do
      expect {
        concurrently(-> { raise ActiveRecord::RecordNotUnique, "from a worker thread" })
      }.to raise_error(ActiveRecord::RecordNotUnique, /from a worker thread/)
    end
  end

  describe "cleanup" do
    let(:leftover_name) { unique_namespace("crashed") }

    # A crash leaves rows behind. Cleanup has to cope with that on the next run,
    # and running it twice must not be an error — otherwise the first failure
    # poisons every run after it.
    it "is idempotent after a simulated crash" do
      InfrastructureCheckpoint.create!(name: leftover_name)

      cleanup = -> { InfrastructureCheckpoint.where("name LIKE ?", "#{leftover_name}%").delete_all }

      expect(cleanup.call).to eq(1)
      expect(cleanup.call).to eq(0)
      expect(cleanup.call).to eq(0)
      expect(InfrastructureCheckpoint.exists?(name: leftover_name)).to be(false)
    end
  end

  describe "factories" do
    it "builds a valid object" do
      expect(build(:infrastructure_checkpoint)).to be_valid
    end

    it "creates only what the object needs" do
      checkpoint = create(:infrastructure_checkpoint)

      expect(checkpoint.counter).to eq(0)
      expect(InfrastructureCheckpoint.count).to eq(1), "a factory must not create objects nobody asked for"
    end

    it "passes FactoryBot.lint — every factory builds and validates" do
      expect { FactoryBot.lint }.not_to raise_error
    end

    it "contains no real data or PII" do
      names = Array.new(3) { build(:infrastructure_checkpoint).name }

      expect(names).to all(match(/\Acheckpoint-\d+\z/))
    end
  end

  describe "release evidence" do
    it "records the commit, the environment and the duration of a run" do
      metadata_path = Rails.root.join("tmp/test-results/rspec-metadata.json")
      skip "run bin/test first" unless metadata_path.exist?

      metadata = JSON.parse(metadata_path.read)

      expect(metadata).to include("commit", "branch", "environment", "duration_ms", "result", "type")
      expect(metadata["environment"]).to eq("test")
    end
  end
end
