require "rails_helper"

# Every ownership rule of doc 04 §3.2, proved by a negative case against real
# PostgreSQL — not against a model validation that a console, an import or a
# future Command could bypass (Annex D §5, AC2/AC3/AC4/AC5/AC6/AC7).
#
# **Why `SET CONSTRAINTS ALL IMMEDIATE` appears here.** The composite key is
# DEFERRABLE INITIALLY DEFERRED, so it is evaluated at COMMIT; the suite runs
# each example inside a transaction that is rolled back, and a deferred check in
# a transaction that never commits never runs. Asking for the check explicitly is
# what makes these examples assert the same thing production does at COMMIT,
# rather than passing because nothing was ever verified. The alternative —
# turning off transactional tests here — would trade a precise assertion for
# cleanup code, and the examples that genuinely need a real COMMIT are in
# `team_ownership_concurrency_spec.rb`.
RSpec.describe "the ownership constraints of a Team", type: :integration do
  let(:owner) { create(:user) }
  let(:team) { create(:team, owner: owner) }

  # The commit-time verification, on demand. Named for what it stands in for.
  #
  # A violation aborts the transaction, exactly as it would at COMMIT, so nothing
  # runs after it in the same example — the rollback the suite performs between
  # examples is what cleans up, and an example that continued would be asserting
  # against a transaction PostgreSQL has already refused.
  def commit_time_check!
    ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
  end

  describe "a Team must have an OWNER (AC3)" do
    it "refuses a Team whose owner has no membership at all" do
      Team.create!(name: "Orphan", slug: "orphan-#{SecureRandom.hex(4)}", owner_user_id: owner.id)

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "refuses a Team whose owner is only an ADMIN" do
      other = create(:user)
      orphan = Team.create!(name: "Wrong role", slug: "wrong-role-#{SecureRandom.hex(4)}",
        owner_user_id: other.id)
      create(:team_member, :admin, team: orphan, user: other)

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "accepts the Team and its OWNER written in one transaction, in that order" do
      # The keys are circular, so this only works because the composite one is
      # deferred. It is the shape `CreateTeam` relies on.
      created = Team.create!(name: "Founded", slug: "founded-#{SecureRandom.hex(4)}",
        owner_user_id: owner.id)
      TeamMember.create!(team: created, user: owner, role: "OWNER", status: "ACTIVE",
        joined_at: Time.current)

      expect { commit_time_check! }.not_to raise_error
    end
  end

  describe "one active OWNER per Team (AC2)" do
    # Two layers, asserted apart. The domain now refuses a membership born OWNER
    # as well as one edited into it, so going through Active Record no longer
    # reaches the index — and a single example would silently stop testing the
    # database the moment the domain answers first. This file is about what
    # PostgreSQL enforces, so the database example bypasses the domain on
    # purpose; the domain example lives in
    # `spec/security/team_ownership_escalation_spec.rb`.
    it "refuses a second OWNER + ACTIVE membership, in the database" do
      team

      expect {
        TeamMember.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: team.id, user_id: create(:user).id,
          role: "OWNER", status: "ACTIVE", joined_at: Time.current,
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_one_active_owner_per_team/)
    end

    it "refuses a second OWNER + ACTIVE membership, in the domain" do
      team

      expect { create(:team_member, :owner, team: team, user: create(:user)) }
        .to raise_error(ActiveRecord::RecordInvalid, /explicit transfer/i)
    end

    # The seat is held while the Team waits for recovery, not only while the
    # OWNER is ACTIVE — otherwise the recovery state would be the one moment the
    # Team could be taken.
    it "refuses a second living OWNER while the Team is in OWNERSHIP_RECOVERY_REQUIRED" do
      SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE,
        team: team, user_id: team.owner_membership.user.external_id)

      expect(team.reload.status).to eq("OWNERSHIP_RECOVERY_REQUIRED")
      expect {
        TeamMember.insert_all!([ {
          id: Opanel::Identifier.generate, team_id: team.id, user_id: create(:user).id,
          role: "OWNER", status: "ACTIVE", joined_at: Time.current,
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_one_active_owner_per_team/)
    end

    it "allows a former OWNER to remain on the Team in another status" do
      team
      create(:team_member, :owner, :removed, team: team, user: create(:user))

      expect(team.team_members.where(role: "OWNER").count).to eq(2)
      expect(team.team_members.where(role: "OWNER", status: "ACTIVE").count).to eq(1)
    end

    it "allows any number of ADMINs" do
      team
      create(:team_member, :admin, team: team, user: create(:user))
      create(:team_member, :admin, team: team, user: create(:user))

      expect(team.team_members.where(role: "ADMIN", status: "ACTIVE").count).to eq(2)
    end
  end

  describe "`owner_user_id` agrees with the membership (AC4)" do
    it "refuses pointing the Team at a user who is not its OWNER" do
      member = create(:team_member, team: team, user: create(:user))
      team.update_columns(owner_user_id: member.user_id)

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "refuses returning to ACTIVE while the OWNER is suspended" do
      recovering = create(:team, :ownership_recovery_required, owner: owner)
      recovering.update_columns(status: "ACTIVE")

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "keeps the generated mirror in step with the Team's status" do
      expect(team.reload.read_attribute(:owner_membership_status)).to eq("ACTIVE")

      recovering = create(:team, :ownership_recovery_required, owner: create(:user))

      expect(recovering.reload.read_attribute(:owner_membership_status)).to eq("SUSPENDED")
      expect(recovering.reload.read_attribute(:owner_role)).to eq("OWNER")
    end

    it "refuses a write to the generated columns, so ownership cannot be faked" do
      expect { ActiveRecord::Base.connection.execute(<<~SQL.squish) }
        UPDATE teams SET owner_role = 'ADMIN' WHERE id = #{ActiveRecord::Base.connection.quote(team.id)}
      SQL
        .to raise_error(ActiveRecord::StatementInvalid, /generated column/)
    end
  end

  describe "the OWNER cannot leave in place (AC5)" do
    before { team }

    it "refuses demoting the OWNER" do
      membership = team.team_members.find_by(user_id: owner.id)
      membership.update_columns(role: "ADMIN")

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "refuses removing the OWNER" do
      membership = team.team_members.find_by(user_id: owner.id)
      membership.update_columns(status: "REMOVED")

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "refuses deleting the OWNER's membership row" do
      team.team_members.find_by(user_id: owner.id).delete

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "refuses suspending the OWNER unless the Team enters recovery in the same transaction" do
      team.team_members.find_by(user_id: owner.id).update_columns(status: "SUSPENDED")

      expect { commit_time_check! }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)
    end

    it "accepts the suspension when the Team moves with it (AC10)" do
      team.team_members.find_by(user_id: owner.id).update_columns(status: "SUSPENDED")
      team.update_columns(status: "OWNERSHIP_RECOVERY_REQUIRED")

      expect { commit_time_check! }.not_to raise_error
    end
  end

  describe "one membership per person per Team (AC6)" do
    it "refuses a duplicate membership" do
      member = create(:team_member, team: team, user: create(:user))

      expect { create(:team_member, :viewer, team: team, user: member.user) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_on_team_id_and_user_id/)
    end

    it "refuses re-adding somebody whose membership was REMOVED, keeping the audit row" do
      removed = create(:team_member, :removed, team: team, user: create(:user))

      expect { create(:team_member, team: team, user: removed.user) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_team_members_on_team_id_and_user_id/)
      expect(removed.reload.status).to eq("REMOVED")
    end

    it "allows the same person in another Team" do
      member = create(:team_member, team: team, user: create(:user))
      elsewhere = create(:team)

      expect { create(:team_member, team: elsewhere, user: member.user) }.not_to raise_error
    end
  end

  describe "the slug is unique among Teams that are not deleted (AC7)" do
    it "refuses a duplicate slug" do
      create(:team, slug: "acme")

      expect { create(:team, slug: "acme") }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_teams_unique_slug_when_not_deleted/)
    end

    it "frees the slug once the Team is soft-deleted" do
      first = create(:team, slug: "acme")
      first.update_columns(deleted_at: Time.current)

      expect { create(:team, slug: "acme") }.not_to raise_error
    end
  end

  describe "a REMOVED membership preserves the audit trail (AC9)" do
    it "keeps the row, its role and when the person joined" do
      joined = 3.months.ago.change(usec: 0)
      member = create(:team_member, :admin, team: team, user: create(:user), joined_at: joined)

      member.update!(status: "REMOVED")

      expect(member.reload).to have_attributes(status: "REMOVED", role: "ADMIN", joined_at: joined)
    end

    it "refuses to delete a Team that still has memberships, so history cannot be dropped" do
      create(:team_member, team: team, user: create(:user))

      expect { ActiveRecord::Base.connection.execute(<<~SQL.squish) }
        DELETE FROM teams WHERE id = #{ActiveRecord::Base.connection.quote(team.id)}
      SQL
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "the constraints survive `db:schema:load`" do
    # The whole design turns on this. A `CONSTRAINT TRIGGER` would have been a
    # shorter way to write the invariant and the Ruby schema dumper does not emit
    # one: it would exist in a migrated database and be silently absent from
    # every database built from the dump — including the one this suite runs
    # against. This example is what proves the choice actually held, because the
    # test database *is* loaded from `db/schema.rb`.
    def constraint_names(query)
      ActiveRecord::Base.connection.select_values(query)
    end

    it "carries the composite deferrable foreign key" do
      row = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT condeferrable, condeferred FROM pg_constraint
        WHERE conname = 'fk_teams_active_owner_membership'
      SQL

      expect(row).to include("condeferrable" => true, "condeferred" => true)
    end

    it "carries the three unique indexes the invariant needs" do
      names = constraint_names(<<~SQL.squish)
        SELECT indexname FROM pg_indexes WHERE tablename IN ('teams', 'team_members')
      SQL

      expect(names).to include(
        "index_team_members_on_team_id_and_user_id",
        "index_team_members_one_active_owner_per_team",
        "index_team_members_owner_reference",
        "index_teams_unique_slug_when_not_deleted"
      )
    end

    it "carries both generated columns" do
      generated = constraint_names(<<~SQL.squish)
        SELECT attname FROM pg_attribute
        WHERE attrelid = 'teams'::regclass AND attgenerated = 's'
      SQL

      expect(generated).to contain_exactly("owner_role", "owner_membership_status")
    end
  end
end
