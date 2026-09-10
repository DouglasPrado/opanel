require "rails_helper"

# The constraints of doc 09 §18, proved against real PostgreSQL by the negative case.
#
# Every example here bypasses the model where possible, so what is being tested is
# the database and not the Ruby validation sitting in front of it.
RSpec.describe "environment constraints", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }

  describe "UNIQUE(project_id, slug) WHERE deleted_at IS NULL (AC2)" do
    it "refuses a second living Environment with the same slug in the same Project" do
      create(:environment, project: project, cluster: cluster, slug: "production")

      expect {
        Environment.insert_all!([ {
          id: Opanel::Identifier.generate, project_id: project.id, cluster_id: cluster.id,
          team_id: team.id, name: "Production again", slug: "production",
          type: "PRODUCTION", status: "READY",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_environments_unique_slug_per_project_when_not_deleted/)
    end

    it "allows the slug of a deleted Environment to be taken again" do
      create(:environment, :deleted, project: project, cluster: cluster, slug: "production")

      expect { create(:environment, project: project, cluster: cluster, slug: "production") }
        .to change(Environment, :count).by(1)
    end

    # AC3 extension: two Projects may have Environments with the same slug.
    it "allows the same slug in a different Project" do
      other = create(:project, team: team)
      create(:environment, project: project, cluster: cluster, slug: "production")

      expect { create(:environment, project: other, cluster: cluster, slug: "production") }
        .to change(Environment, :count).by(1)
    end
  end

  describe "the CHECK constraints" do
    def insert(**attributes)
      Environment.insert_all!([ {
        id: Opanel::Identifier.generate, project_id: project.id, cluster_id: cluster.id,
        team_id: team.id, name: "Test", slug: "test", type: "DEVELOPMENT",
        status: "READY", created_at: Time.current, updated_at: Time.current
      }.merge(attributes) ])
    end

    it "refuses an id that is not a ULID" do
      expect { insert(id: "not-a-ulid") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_id_is_ulid/)
    end

    it "refuses a blank name" do
      expect { insert(name: "   ") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_name_present/)
    end

    it "refuses a name past 120 characters" do
      expect { insert(name: "a" * 121) }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_name_present/)
    end

    it "refuses a slug that is not a URL segment" do
      expect { insert(slug: "Test Env") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_slug_format/)
    end

    it "refuses a slug shorter than 2 characters" do
      expect { insert(slug: "p") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_slug_format/)
    end

    it "refuses a type outside the documented list" do
      expect { insert(type: "STAGING") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_type_is_known/)
    end

    it "accepts the five documented types" do
      %w[PRODUCTION HOMOLOGATION DEVELOPMENT PREVIEW CUSTOM].each_with_index do |env_type, index|
        expect { insert(type: env_type, slug: "env-#{index}") }.not_to raise_error
      end
    end

    it "refuses a status outside the documented list" do
      expect { insert(status: "WAITING") }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_status_is_known/)
    end

    it "accepts the five documented statuses" do
      %w[PROVISIONING READY DEGRADED PAUSED DELETING].each_with_index do |st, index|
        expect { insert(status: st, slug: "env-#{index}") }.not_to raise_error
      end
    end

    # AC5: PRODUCTION must not have auto_promote_secrets = true.
    it "refuses PRODUCTION with auto_promote_secrets = true" do
      expect { insert(type: "PRODUCTION", auto_promote_secrets: true) }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_production_no_auto_promote/)
    end

    it "allows PRODUCTION with auto_promote_secrets = false" do
      expect { insert(type: "PRODUCTION", auto_promote_secrets: false) }.not_to raise_error
    end

    it "allows non-PRODUCTION types with auto_promote_secrets = true" do
      %w[HOMOLOGATION DEVELOPMENT PREVIEW CUSTOM].each_with_index do |env_type, index|
        expect { insert(type: env_type, auto_promote_secrets: true, slug: "env-#{index}") }
          .not_to raise_error
      end
    end

    # Revisions: applied cannot exceed desired.
    it "refuses applied_revision > desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 6) }
        .to raise_error(ActiveRecord::StatementInvalid, /environments_applied_revision_not_ahead/)
    end

    it "allows applied_revision = desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 5) }.not_to raise_error
    end

    it "allows applied_revision < desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 3) }.not_to raise_error
    end

    it "allows applied_revision = nil" do
      expect { insert(desired_revision: 1, applied_revision: nil) }.not_to raise_error
    end
  end

  describe "the foreign keys" do
    it "refuses an Environment whose Project does not exist" do
      expect {
        Environment.insert_all!([ {
          id: Opanel::Identifier.generate, project_id: Opanel::Identifier.generate,
          cluster_id: cluster.id, team_id: team.id, name: "Test", slug: "test",
          type: "DEVELOPMENT", status: "READY",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "refuses an Environment whose Cluster does not exist" do
      expect {
        Environment.insert_all!([ {
          id: Opanel::Identifier.generate, project_id: project.id,
          cluster_id: Opanel::Identifier.generate, team_id: team.id,
          name: "Test", slug: "test", type: "DEVELOPMENT", status: "READY",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "refuses an Environment whose Team does not exist" do
      expect {
        Environment.insert_all!([ {
          id: Opanel::Identifier.generate, project_id: project.id,
          cluster_id: cluster.id, team_id: Opanel::Identifier.generate,
          name: "Test", slug: "test", type: "DEVELOPMENT", status: "READY",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    # RESTRICT: Projects with Environments cannot be deleted.
    it "refuses to delete a Project that has Environments" do
      create(:environment, project: project, cluster: cluster)

      expect { project.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    # RESTRICT: Clusters with Environments cannot be deleted.
    it "refuses to delete a Cluster that has Environments" do
      create(:environment, project: project, cluster: cluster)

      expect { cluster.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "the keyset pagination index" do
    it "reaches a page through index_environments_on_project_id_and_id" do
      # Create enough data across multiple projects so the composite index
      # (project_id, id) becomes cheaper than walking the primary key,
      # which would have to read and discard rows from other projects.
      other_projects = create_list(:project, 3, team: team)
      other_projects.each do |p|
        create_list(:environment, 5, project: p, cluster: cluster)
      end

      # Target project gets fewer environments so selective filtering is needed.
      create_list(:environment, 3, project: project, cluster: cluster)

      # Statistics give the planner accurate row counts per project,
      # making the composite index genuinely cheaper than a pkey walk.
      Environment.connection.execute("ANALYZE environments")

      plan = Environment.connection.select_value(<<~SQL.squish)
        SET LOCAL enable_seqscan = off;
        EXPLAIN (FORMAT JSON)
        SELECT * FROM environments
        WHERE project_id = '#{project.id}' AND id > '00000000000000000000000000'
        ORDER BY id LIMIT 26
      SQL

      expect(plan.to_s).to include("index_environments_on_project_id_and_id")
    end
  end
end

# AC9: Cluster DEGRADED produces a block with explicit message (CreateEnvironment).
RSpec.describe "Cluster status validation in CreateEnvironment", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:user) { create(:user) }

  before do
    create(:team_member, :admin, team: team, user: user)
  end

  describe "AC9 — refusing creation on DEGRADED cluster" do
    it "refuses to create an Environment on a DEGRADED cluster with an explicit message" do
      degraded_cluster = create(:cluster, team: team, status: "DEGRADED", observed_at: Time.current)

      result = CreateEnvironment.call(
        actor: user,
        project: project,
        cluster: degraded_cluster,
        name: "Production",
        slug: "prod",
        type: "PRODUCTION"
      )

      expect(result).to be_failure
      expect(result.code).to eq("VALIDATION_ERROR")
      expect(result.message).to match(/not ready/i)
      expect(result.details[:field]).to eq("cluster")
    end
  end

  describe "AC9 — allowing creation on READY cluster" do
    it "allows creation of an Environment on a READY cluster" do
      ready_cluster = create(:cluster, :bootstrapped, team: team)

      result = CreateEnvironment.call(
        actor: user,
        project: project,
        cluster: ready_cluster,
        name: "Production",
        slug: "prod",
        type: "PRODUCTION"
      )

      expect(result).to be_success
      env = result.value.fetch(:environment)
      expect(env).to be_persisted
      expect(env.cluster).to eq(ready_cluster)
    end
  end
end
