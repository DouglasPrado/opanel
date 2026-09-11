require "rails_helper"

# The domain half of the membership rules (doc 04 §5.1 and §5.2). The database
# half — the constraints — is proved in `spec/integration`; these are the rules
# that give a caller a stable error instead of a raised PostgreSQL exception.
RSpec.describe TeamMember, type: :model do
  describe "roles" do
    it "knows exactly the roles of doc 04 §5.1 that this Milestone ships" do
      # BILLING is listed there as optional for a later phase and is deliberately
      # out of this Story's scope; adding it is an expand migration on the CHECK.
      expect(described_class::ROLES).to eq(%w[OWNER ADMIN DEVELOPER VIEWER])
    end

    it "refuses a role that is not one of them" do
      member = build(:team_member, role: "SUPERUSER")

      expect(member).not_to be_valid
      expect(member.errors[:role]).to be_present
    end

    it "refuses promoting an existing membership to OWNER" do
      member = create(:team_member, :admin)

      member.role = "OWNER"

      expect(member).not_to be_valid
      expect(member.errors[:role].join).to match(/transfer/i)
    end

    it "allows an ordinary role change between the non-owner roles" do
      member = create(:team_member, :admin)

      member.role = "VIEWER"

      expect(member).to be_valid
    end
  end

  describe "the membership lifecycle" do
    it "knows exactly the statuses of doc 04 §5.2" do
      expect(described_class::STATUSES).to eq(%w[INVITED ACTIVE SUSPENDED REMOVED])
    end

    {
      "INVITED" => %w[ACTIVE REMOVED],
      "ACTIVE" => %w[SUSPENDED REMOVED],
      "SUSPENDED" => %w[ACTIVE REMOVED],
      "REMOVED" => []
    }.each do |from, allowed|
      (described_class::STATUSES - [ from ]).each do |to|
        if allowed.include?(to)
          it "allows #{from} → #{to}" do
            member = create(:team_member, status: from, joined_at: from == "INVITED" ? nil : Time.current)

            member.status = to
            member.joined_at ||= Time.current

            expect(member).to be_valid
          end
        else
          it "refuses #{from} → #{to}" do
            member = create(:team_member, status: from, joined_at: from == "INVITED" ? nil : Time.current)

            member.status = to

            expect(member).not_to be_valid
            expect(member.errors[:status].join).to match(/#{from}/)
          end
        end
      end
    end

    it "treats REMOVED as terminal, so a removed member cannot be silently restored" do
      member = create(:team_member, :removed)

      member.status = "ACTIVE"

      expect(member).not_to be_valid
    end

    it "keeps `joined_at` once set, so the audit trail survives removal" do
      joined = 2.months.ago.change(usec: 0)
      member = create(:team_member, joined_at: joined)

      member.update!(status: "REMOVED")

      expect(member.reload.joined_at).to eq(joined)
    end
  end

  describe "what the rest of the application asks a membership" do
    it "answers `owner?` only for an OWNER" do
      team = create(:team)

      expect(team.team_members.sole).to be_owner
      expect(create(:team_member, :admin, team: team)).not_to be_owner
    end

    it "answers `grants_access?` only while ACTIVE" do
      expect(create(:team_member)).to be_grants_access
      expect(create(:team_member, :suspended)).not_to be_grants_access
      expect(create(:team_member, :invited)).not_to be_grants_access
      expect(create(:team_member, :removed)).not_to be_grants_access
    end
  end
end
