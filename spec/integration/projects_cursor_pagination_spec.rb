require "rails_helper"

# AC6 — the listing uses a cursor and stays stable while rows are being inserted.
#
# "Stable" is asserted as a property of the *whole traversal*: every Project that
# existed when paging started is served exactly once. Repeating one is the
# failure `OFFSET` produces under a concurrent insert, and it is the one a reader
# actually notices.
RSpec.describe ProjectsForTeam, :integration do
  let(:team) { create(:team) }
  let(:actor) { team.owner }

  def page(cursor: nil, limit: 3)
    described_class.call(actor: actor, team: team, cursor: cursor, limit: limit)
  end

  def slugs(result) = result.entries.map(&:slug)

  describe "paging" do
    before { 7.times { |n| create(:project, team: team, slug: "p-#{n}") } }

    it "returns at most the requested page size" do
      expect(page(limit: 3).entries.length).to eq(3)
    end

    it "offers a cursor while more rows exist and none on the last page" do
      first = page(limit: 3)
      expect(first.next_cursor).to be_present

      last = page(cursor: page(cursor: first.next_cursor, limit: 3).next_cursor, limit: 3)
      expect(last.next_cursor).to be_nil
    end

    it "walks the whole set without repeating or skipping a row" do
      seen = []
      cursor = nil

      loop do
        result = page(cursor: cursor, limit: 3)
        seen.concat(slugs(result))
        cursor = result.next_cursor
        break if cursor.nil?
      end

      expect(seen).to match_array((0..6).map { |n| "p-#{n}" })
      expect(seen.uniq.length).to eq(seen.length)
    end
  end

  # The criterion itself. Rows are inserted *between* pages, which is what a
  # second user creating a Project does while somebody else is scrolling.
  #
  # The failure a concurrent insert actually produces is a **duplicate**, not a
  # skip: a row landing before the reader's position shifts everything right, so
  # the next window re-reads something already served. (A skip is what a *delete*
  # produces.) The first version of this file asserted the wrong direction and
  # the control below is what proved it — which is the whole reason the control
  # is here.
  describe "under concurrent inserts (AC6)" do
    # Deliberately lower than every ULID the application generates, so the row
    # lands *behind* the reader. A ULID is monotonic, so this cannot happen in
    # production — which is exactly the property being tested, and asserting it
    # requires forcing the case the property forbids.
    def insert_behind(nth)
      Project.insert_all!([ {
        id: "#{'0' * 25}#{nth}", team_id: team.id, name: "Early", slug: "early-#{nth}",
        status: "ACTIVE", created_at: Time.current, updated_at: Time.current
      } ])
    end

    it "serves every pre-existing Project exactly once" do
      original = (0..5).map { |n| create(:project, team: team, slug: "p-#{n}").slug }

      seen = []
      cursor = nil
      round = 0

      loop do
        result = page(cursor: cursor, limit: 2)
        seen.concat(slugs(result))
        cursor = result.next_cursor

        insert_behind(round)
        round += 1

        break if cursor.nil? || round > 20
      end

      expect(seen.tally.select { |_, count| count > 1 }).to be_empty
      expect(original - seen).to be_empty, "rows were skipped: #{(original - seen).inspect}"
    end

    # The control. Without it the example above proves only that *something*
    # walked the list. This runs the same traversal against the same inserts with
    # `OFFSET` and watches it repeat rows — so the assertion above is
    # discriminating rather than trivially true.
    it "is a property of the cursor: the same traversal with OFFSET repeats rows" do
      (0..5).each { |n| create(:project, team: team, slug: "p-#{n}") }

      seen = []
      offset = 0
      round = 0

      loop do
        rows = team.projects.active.order(:id).offset(offset).limit(2).pluck(:slug)
        break if rows.empty?

        seen.concat(rows)
        offset += 2

        insert_behind(round)
        round += 1

        break if round > 20
      end

      expect(seen.tally.select { |_, count| count > 1 }).not_to be_empty,
        "OFFSET happened not to repeat anything, so the cursor example above proves nothing"
    end
  end

  describe "the tenancy boundary" do
    it "never returns another Team's Projects (AC4)" do
      create(:project, team: create(:team), slug: "theirs")
      create(:project, team: team, slug: "ours")

      expect(slugs(page)).to eq([ "ours" ])
    end

    it "returns nothing for an actor with no membership" do
      create(:project, team: team, slug: "ours")

      expect(described_class.call(actor: create(:user), team: team, limit: 3).entries).to be_empty
    end

    it "returns nothing once the membership is suspended" do
      create(:project, team: team, slug: "ours")
      team.team_members.find_by(user_id: actor.id).update_columns(status: "SUSPENDED")

      expect(page.entries).to be_empty
    end
  end

  describe "what the listing shows" do
    it "hides archived Projects by default and shows them on request" do
      create(:project, team: team, slug: "live")
      create(:project, :archived, team: team, slug: "old")

      expect(slugs(page)).to eq([ "live" ])
      expect(slugs(described_class.call(actor: actor, team: team, include_archived: true)))
        .to match_array(%w[live old])
    end

    it "never shows a soft-deleted Project" do
      create(:project, :deleted, team: team, slug: "gone")

      expect(page.entries).to be_empty
    end
  end

  describe "the cursor itself" do
    it "is an external identifier, not a bare ULID" do
      create_list(:project, 4, team: team)

      expect(page(limit: 2).next_cursor).to match(/\Aprj_[0-9A-HJKMNP-TV-Z]{26}\z/)
    end

    # ADR-0002 §4: a value carrying another type's prefix is a validation
    # failure, never a NOT_FOUND. A malformed cursor must not be able to ask this
    # query anything at all.
    it "refuses a cursor of another type rather than answering with a page" do
      expect { page(cursor: "team_#{Opanel::Identifier.generate}") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "refuses a malformed cursor" do
      expect { page(cursor: "prj_not-a-ulid") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end
  end

  describe "the page size" do
    # Asserted on what comes back rather than on the instance variable behind it:
    # a private read would keep passing if the clamp stopped being applied to the
    # query.
    it "clamps a request for more than the maximum" do
      rows = (0..described_class::MAX_LIMIT).map do |n|
        { id: Opanel::Identifier.generate, team_id: team.id, name: "P#{n}", slug: "p-#{n}",
          status: "ACTIVE", created_at: Time.current, updated_at: Time.current }
      end
      Project.insert_all!(rows)

      expect(described_class.call(actor: actor, team: team, limit: 10_000).entries.length)
        .to eq(described_class::MAX_LIMIT)
    end

    it "clamps a request for zero or less, so a page is never empty by argument" do
      create(:project, team: team, slug: "one")

      expect(described_class.call(actor: actor, team: team, limit: 0).entries.length).to eq(1)
    end
  end
end
