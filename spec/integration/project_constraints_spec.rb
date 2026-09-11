require "rails_helper"

# The constraints of doc 09 §18, proved against real PostgreSQL by the negative
# case — never by reading the migration back.
#
# Every example here bypasses the model where the model would also refuse, so
# what is being tested is the database and not the Ruby validation sitting in
# front of it. A validation is a courtesy to the user; the constraint is what
# holds when the write comes from an import, a console or a race.
RSpec.describe "project constraints", :integration do
  let(:team) { create(:team) }

  describe "UNIQUE(team_id, slug) WHERE deleted_at IS NULL (AC2)" do
    it "refuses a second living Project with the same slug in the same Team" do
      create(:project, team: team, slug: "billing")

      expect {
        Project.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: team.id, name: "Billing again",
          slug: "billing", status: "ACTIVE",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_projects_unique_slug_per_team_when_not_deleted/)
    end

    # The index is partial, and this is the half that makes it so: a Project that
    # was removed must not hold a name in a URL forever.
    it "allows the slug of a deleted Project to be taken again" do
      create(:project, :deleted, team: team, slug: "billing")

      expect { create(:project, team: team, slug: "billing") }.to change(Project, :count).by(1)
    end

    # AC3, in the database rather than only in the Command: uniqueness is per
    # Team, so two Teams may both have a `billing`.
    it "allows the same slug in a different Team" do
      other = create(:team)
      create(:project, team: team, slug: "billing")

      expect { create(:project, team: other, slug: "billing") }.to change(Project, :count).by(1)
    end
  end

  describe "the CHECK constraints" do
    def insert(**attributes)
      Project.insert_all!([ {
        id: Opanel::Identifier.generate, team_id: team.id, name: "Billing", slug: "billing",
        status: "ACTIVE", created_at: Time.current, updated_at: Time.current
      }.merge(attributes) ])
    end

    it "refuses an id that is not a ULID" do
      expect { insert(id: "not-a-ulid") }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_id_is_ulid/)
    end

    it "refuses a blank name" do
      expect { insert(name: "   ") }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_name_present/)
    end

    it "refuses a name past the documented length" do
      expect { insert(name: "a" * 121) }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_name_present/)
    end

    it "refuses a slug that is not a URL segment" do
      expect { insert(slug: "Billing Ops") }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_slug_format/)
    end

    it "refuses a status outside doc 09 §5.1" do
      expect { insert(status: "PAUSED") }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_status_is_known/)
    end

    it "accepts the three statuses doc 09 §5.1 names" do
      %w[ACTIVE ARCHIVED DELETING].each_with_index do |status, index|
        expect { insert(status: status, slug: "billing-#{index}") }.not_to raise_error
      end
    end

    # `default_environment_id` has no foreign key until `M01-11` creates
    # `environments`. Absent is allowed — doc 09 §5.1 calls it a UX reference, so
    # a Project whose default was removed must still load. Malformed is not.
    it "allows default_environment_id to be absent" do
      expect { insert(default_environment_id: nil) }.not_to raise_error
    end

    it "refuses a default_environment_id that is not a ULID" do
      expect { insert(default_environment_id: "env-1") }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_default_environment_id_is_ulid/)
    end

    it "refuses a description past the documented length" do
      expect { insert(description: "a" * 2001) }
        .to raise_error(ActiveRecord::StatementInvalid, /projects_description_length/)
    end
  end

  describe "the foreign key to teams" do
    it "refuses a Project whose Team does not exist" do
      expect {
        Project.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: Opanel::Identifier.generate,
          name: "Orphan", slug: "orphan", status: "ACTIVE",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    # RESTRICT, not CASCADE: doc 09 §25 makes removal a lifecycle, and a Team
    # deleted out from under its Projects would destroy desired state the runtime
    # is still converging toward.
    it "refuses to delete a Team that still has Projects" do
      create(:project, team: team)

      expect { team.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "the index the listing depends on (AC6)" do
    it "reaches a page of one Team's Projects through index_projects_on_team_id_and_id" do
      create_list(:project, 3, team: team)

      plan = Project.connection.select_value(<<~SQL.squish)
        SET LOCAL enable_seqscan = off;
        EXPLAIN (FORMAT JSON)
        SELECT * FROM projects
        WHERE team_id = '#{team.id}' AND id > '00000000000000000000000000'
        ORDER BY id LIMIT 26
      SQL

      # Asserts the shape of the query, not the size of the fixture: with
      # `enable_seqscan` off a planner that had no usable index would still
      # report a sequential scan at a punitive cost, so this fails when the index
      # is dropped rather than when the table happens to be small.
      expect(plan.to_s).to include("index_projects_on_team_id_and_id")
    end
  end
end
