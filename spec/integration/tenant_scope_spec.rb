require "rails_helper"

# AC5 and AC7, against real PostgreSQL.
#
# The helper is what turns Annex C §7.3 from an instruction people remember into a
# thing the code does. These examples check the property that matters — a row
# outside the boundary is unreachable, not merely forbidden — and the property
# that makes suspension work without touching sessions.
RSpec.describe TenantScope, type: :integration do
  let(:owner) { create(:user) }
  let!(:team) { create(:team, owner: owner) }
  let(:outsider) { create(:user) }
  let!(:outsider_team) { create(:team, owner: outsider) }

  describe "the boundary it puts in the query" do
    it "returns only Teams the actor has an active membership of" do
      expect(described_class.for(owner, Team).relation.pluck(:id)).to eq([ team.id ])
      expect(described_class.for(outsider, Team).relation.pluck(:id)).to eq([ outsider_team.id ])
    end

    it "cannot reach another Team by id" do
      expect(described_class.for(outsider, Team).find(team.id)).to be_nil
    end

    it "cannot reach another Team by external id either" do
      found = described_class.for(outsider, Team).find_by_external_id(:team, team.external_id)

      expect(found).to be_nil
    end

    it "answers a forbidden row and an absent row the same way" do
      forbidden = described_class.for(outsider, Team).find(team.id)
      absent = described_class.for(outsider, Team).find(Opanel::Identifier.generate)

      expect(forbidden).to eq(absent)
      expect(forbidden).to be_nil
    end

    it "returns nothing at all for an anonymous actor" do
      expect(described_class.for(nil, Team).relation).to be_empty
    end

    # The boundary is in the SQL, not applied afterwards in Ruby. A filter applied
    # after the fact still loads the row, which is how "scoped" implementations
    # leak through logs, counts and pagination totals.
    it "puts the boundary in the SQL" do
      sql = described_class.for(owner, Team).relation.to_sql

      expect(sql).to include("team_members")
      expect(sql).to include(owner.id)
    end
  end

  describe "a model with no boundary registered" do
    # Deny by default, for data. A model nobody has thought about must not fall
    # through to "everything".
    it "raises rather than returning every row" do
      expect { described_class.for(owner, User).relation }
        .to raise_error(TenantScope::UnscopedRelation, /leaks across Teams/)
    end
  end

  describe "a membership that is suspended (AC7)" do
    it "stops resolving on the very next query, with nothing invalidated" do
      member = create(:user)
      membership = create(:team_member, team: team, user: member)

      expect(described_class.for(member, Team).find(team.id)).to eq(team)

      membership.update!(status: "SUSPENDED")

      expect(described_class.for(member, Team).find(team.id)).to be_nil
    end

    it "denies the Policy on the next request too" do
      member = create(:user)
      membership = create(:team_member, team: team, user: member)

      expect(Opanel::Authorization.authorize(member, :view, team)).to be_allowed

      membership.update!(status: "SUSPENDED")

      decision = Opanel::Authorization.authorize(member, :view, team)
      expect(decision).to be_denied
      expect(decision.reason).to eq(:no_membership)
    end
  end
end
