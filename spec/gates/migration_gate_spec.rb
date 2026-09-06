require "spec_helper"
require "tmpdir"
require_relative "../../lib/gates/migration_gate"

# A gate nobody proved can fail is a gate that passes forever. Each rule below is
# planted with a violation and must be detected; each is then shown to accept the
# compliant form, so the gate is not simply refusing everything.
RSpec.describe Opanel::Gates::MigrationGate do
  def violations_for(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "20260101000000_example.rb")
      File.write(path, source)
      described_class.new(path).violations
    end
  end

  def rules_for(source) = violations_for(source).map(&:rule)

  describe "REVERSIBILITY" do
    it "rejects `up` without `down` and without a forward-fix plan" do
      violations = violations_for(<<~RUBY)
        class Example < ActiveRecord::Migration[8.1]
          def up
            execute "UPDATE infrastructure_checkpoints SET counter = 0"
          end
        end
      RUBY

      expect(violations.map(&:rule)).to include("REVERSIBILITY")
      expect(violations.first.message).to include("without `down`")
      expect(violations.first.remedy).to include("migration-forward-fix")
    end

    it "accepts `up` with `down`" do
      expect(rules_for(<<~RUBY)).not_to include("REVERSIBILITY")
        class Example < ActiveRecord::Migration[8.1]
          def up
            execute "SELECT 1"
          end

          def down
            execute "SELECT 1"
          end
        end
      RUBY
    end

    it "accepts `up` without `down` when a forward-fix plan is declared" do
      expect(rules_for(<<~RUBY)).not_to include("REVERSIBILITY")
        # migration-forward-fix: data-only backfill; a bad rollout is corrected by
        # re-running the backfill, not by reverting the migration.
        class Example < ActiveRecord::Migration[8.1]
          def up
            execute "SELECT 1"
          end
        end
      RUBY
    end

    it "rejects raw `execute` inside `change`" do
      expect(rules_for(<<~RUBY)).to include("REVERSIBILITY")
        class Example < ActiveRecord::Migration[8.1]
          def change
            execute "SELECT 1"
          end
        end
      RUBY
    end

    it "accepts raw `execute` wrapped in `reversible`" do
      expect(rules_for(<<~RUBY)).not_to include("REVERSIBILITY")
        class Example < ActiveRecord::Migration[8.1]
          def change
            reversible do |direction|
              direction.up { execute "SELECT 1" }
              direction.down { execute "SELECT 2" }
            end
          end
        end
      RUBY
    end

    it "rejects `remove_column` inside `change` without the column type" do
      expect(rules_for(<<~RUBY)).to include("REVERSIBILITY")
        # migration-phase: contract
        # migration-contract-ref: M00-02
        class Example < ActiveRecord::Migration[8.1]
          def change
            remove_column :infrastructure_checkpoints, :counter
          end
        end
      RUBY
    end
  end

  describe "CONTRACT_PHASE" do
    it "rejects a column removal without a contract-phase marker" do
      violations = violations_for(<<~RUBY)
        class Example < ActiveRecord::Migration[8.1]
          def change
            remove_column :infrastructure_checkpoints, :counter, :bigint, default: 0, null: false
          end
        end
      RUBY

      expect(violations.map(&:rule)).to include("CONTRACT_PHASE")
      expect(violations.find { |violation| violation.rule == "CONTRACT_PHASE" }.message)
        .to include("migration-phase: contract")
    end

    it "rejects a contract-phase marker without a decision reference" do
      violations = violations_for(<<~RUBY)
        # migration-phase: contract
        class Example < ActiveRecord::Migration[8.1]
          def change
            drop_table :infrastructure_checkpoints do |t|
              t.string :name
            end
          end
        end
      RUBY

      contract = violations.find { |violation| violation.rule == "CONTRACT_PHASE" }
      expect(contract).not_to be_nil
      expect(contract.message).to include("migration-contract-ref")
    end

    it "accepts a destructive change that declares phase and reference" do
      expect(rules_for(<<~RUBY)).not_to include("CONTRACT_PHASE")
        # migration-phase: contract
        # migration-contract-ref: ADR-0009
        class Example < ActiveRecord::Migration[8.1]
          def change
            remove_column :infrastructure_checkpoints, :counter, :bigint, default: 0, null: false
          end
        end
      RUBY
    end

    it "detects destructive SQL hidden in an execute call" do
      expect(rules_for(<<~RUBY)).to include("CONTRACT_PHASE")
        # migration-forward-fix: none needed
        class Example < ActiveRecord::Migration[8.1]
          def up
            execute "ALTER TABLE infrastructure_checkpoints DROP COLUMN counter"
          end
        end
      RUBY
    end

    it "ignores a destructive operation that only appears in a comment" do
      expect(rules_for(<<~RUBY)).not_to include("CONTRACT_PHASE")
        # This migration deliberately does not drop_table anything.
        # migration-index-review: new table
        class Example < ActiveRecord::Migration[8.1]
          def change
            create_table(:example) { |t| t.string :name }
          end
        end
      RUBY
    end
  end

  describe "INDEX_SAFETY" do
    it "rejects an index build with neither a review note nor CONCURRENTLY" do
      violations = violations_for(<<~RUBY)
        class Example < ActiveRecord::Migration[8.1]
          def change
            add_index :infrastructure_checkpoints, :counter
          end
        end
      RUBY

      expect(violations.map(&:rule)).to include("INDEX_SAFETY")
      expect(violations.first.remedy).to include("migration-index-review")
    end

    it "rejects CONCURRENTLY without disable_ddl_transaction!" do
      violations = violations_for(<<~RUBY)
        class Example < ActiveRecord::Migration[8.1]
          def change
            add_index :infrastructure_checkpoints, :counter, algorithm: :concurrently
          end
        end
      RUBY

      index = violations.find { |violation| violation.rule == "INDEX_SAFETY" }
      expect(index.message).to include("disable_ddl_transaction!")
    end

    it "accepts CONCURRENTLY with disable_ddl_transaction!" do
      expect(rules_for(<<~RUBY)).not_to include("INDEX_SAFETY")
        class Example < ActiveRecord::Migration[8.1]
          disable_ddl_transaction!

          def change
            add_index :infrastructure_checkpoints, :counter, algorithm: :concurrently
          end
        end
      RUBY
    end

    it "accepts an index build with a review note" do
      expect(rules_for(<<~RUBY)).not_to include("INDEX_SAFETY")
        # migration-index-review: table is created empty in this same migration
        class Example < ActiveRecord::Migration[8.1]
          def change
            create_table(:example) { |t| t.string :name }
            add_index :example, :name
          end
        end
      RUBY
    end

    it "does not treat add_reference with index: false as an index build" do
      expect(rules_for(<<~RUBY)).not_to include("INDEX_SAFETY")
        class Example < ActiveRecord::Migration[8.1]
          def change
            add_reference :example, :other, index: false
          end
        end
      RUBY
    end
  end

  describe "the migrations actually in this repository" do
    it "passes the gate" do
      paths = Dir.glob(File.expand_path("../../db/migrate/*.rb", __dir__))

      expect(paths).not_to be_empty
      expect(described_class.check_paths(paths)).to be_empty
    end
  end
end
