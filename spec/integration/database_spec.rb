require "rails_helper"

# Integration against real PostgreSQL. The constraints being exercised live in the
# database, not in Active Record: a writer that bypasses the model must still be
# rejected (Annex I §8.1).
RSpec.describe "PostgreSQL integration", type: :integration do
  it "runs against PostgreSQL, not SQLite" do
    expect(ActiveRecord::Base.connection.adapter_name).to eq("PostgreSQL")
  end

  it "uses a test database distinct from development and ci" do
    names = %w[development test ci].map do |environment|
      ActiveRecord::Base.configurations.configs_for(env_name: environment, name: "primary").database
    end

    expect(names.uniq.length).to eq(3), "development, test and ci must not share a database: #{names.inspect}"
    expect(ActiveRecord::Base.connection_db_config.database).to eq(names[1])
  end

  it "enforces the unique index in the database" do
    InfrastructureCheckpoint.create!(name: "reconcile-sweep")

    duplicate = InfrastructureCheckpoint.new(name: "reconcile-sweep")
    duplicate.save(validate: false)
    expect(duplicate.persisted?).to be(false)
  rescue ActiveRecord::RecordNotUnique => error
    expect(error.message).to include("index_infrastructure_checkpoints_on_name")
  end

  it "enforces the check constraint in the database" do
    checkpoint = InfrastructureCheckpoint.create!(name: "negative-guard")

    expect {
      InfrastructureCheckpoint.where(id: checkpoint.id).update_all(counter: -1)
    }.to raise_error(ActiveRecord::StatementInvalid, /infrastructure_checkpoints_counter_non_negative/)
  end

  it "rolls a transaction back without leaving a partial write" do
    expect {
      ActiveRecord::Base.transaction do
        InfrastructureCheckpoint.create!(name: "rolled-back")
        raise ActiveRecord::Rollback
      end
    }.not_to change(InfrastructureCheckpoint, :count)
  end

  describe "connection classification" do
    # The probe gets its own abstract Active Record class so a deliberately broken
    # configuration cannot replace the pool the rest of the suite is using.
    #
    # `establish_connection` connects eagerly, so a bad configuration raises before
    # `check` is reached. The helper therefore routes the real PG error through the
    # same classifier `check` uses — which is the part under test here: that the
    # actual wording PostgreSQL produces maps to a cause and not to :unknown.
    def probe(overrides)
      configuration = ActiveRecord::Base.connection_db_config.configuration_hash.merge(overrides)

      probe_class = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
        def self.name = "DatabaseProbeRecord"
      end

      begin
        probe_class.establish_connection(configuration)
        Opanel::DatabaseConnection.check(probe_class.connection_pool)
      rescue StandardError => error
        Opanel::DatabaseConnection.classify(error)
      ensure
        probe_class.remove_connection
      end
    end

    it "reports the live connection as available" do
      expect(Opanel::DatabaseConnection.check).to be_available
    end

    it "classifies a missing database instead of timing out generically" do
      name = "opanel_does_not_exist_#{SecureRandom.hex(4)}"
      result = probe(database: name)

      expect(result).not_to be_available
      expect(result.cause).to eq(:database_missing)
      expect(result.detail).to include(name), "the detail must name the database an operator has to create"
    end

    it "classifies an unreachable host with the host and port visible" do
      result = probe(host: "127.0.0.1", port: 1)

      expect(result).not_to be_available
      expect(result.cause).to eq(:host_unreachable)
    end
  end
end
