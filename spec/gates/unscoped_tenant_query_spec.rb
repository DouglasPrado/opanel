require "rails_helper"
require "rubocop"
require Rails.root.join("lib/rubocop/cop/opanel/unscoped_tenant_query")

# The other half of AC5: *"o lint/fitness reprova busca por ID sem escopo, provado
# por caso negativo"*.
#
# `TenantScope` makes the safe thing easy; this cop makes the unsafe thing
# visible. Both halves are needed, and the second is the one that survives the
# author who has never read Annex C — an unscoped `find` returns the row, so the
# code works, the tests pass, and it leaks.
#
# Every example here plants a violation and asserts the cop sees it, or plants a
# correct call and asserts it does not. A cop with no planted violation is a cop
# nobody knows is wired up.
RSpec.describe RuboCop::Cop::Opanel::UnscopedTenantQuery, type: :gates do
  def offences_in(source)
    config = RuboCop::Config.new({}, "#{Dir.pwd}/.rubocop.yml")
    commissioner = RuboCop::Cop::Commissioner.new([ described_class.new(config) ], [], raise_error: true)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)

    commissioner.investigate(processed).offenses
  end

  describe "what it refuses" do
    it "flags a lookup of a tenant-scoped model by primary key" do
      offences = offences_in("Team.find(params[:id])")

      expect(offences.length).to eq(1)
      expect(offences.first.message).to include("TenantScope")
    end

    it "flags `find_by(id:)`, which is the same thing spelled differently" do
      expect(offences_in("TeamMember.find_by(id: params[:member_id])").length).to eq(1)
    end

    it "flags `find_by!(id:)` too" do
      expect(offences_in("Team.find_by!(id: id)").length).to eq(1)
    end

    it "flags it inside a hash of other conditions, where it is easiest to miss" do
      expect(offences_in("Team.find_by(id: id, status: 'ACTIVE')").length).to eq(1)
    end

    # A first version of this cop matched only a bare-constant receiver, and so
    # caught the canonical spelling while missing fifteen others. Two of those are
    # what a careful author actually writes — `kept` is a real scope on Team, and
    # `where(id:).first` is the acceptance criterion's own words. Each row here is
    # a spelling that leaked past the earlier rule.
    {
      "a chained scope" => "Team.kept.find(params[:id])",
      "where(id:) then first" => "Team.where(id: params[:id]).first",
      "where(id:) then take" => "Team.where(id: params[:id]).take",
      "where(id:) then sole" => "Team.where(id: params[:id]).sole",
      "all" => "Team.all.find_by(id: params[:id])",
      "unscoped" => "Team.unscoped.find(params[:id])",
      "order" => "Team.order(:name).find(params[:id])",
      "includes" => "Team.includes(:team_members).find(params[:id])",
      "joins" => "Team.joins(:team_members).find_by(id: params[:id])",
      "select" => "Team.select(:id).find(params[:id])",
      "lock" => "Team.lock.find(params[:id])",
      "dynamic finder" => "Team.find_by_id(params[:id])",
      "string key" => "Team.find_by('id' => params[:id])",
      "find_or_initialize_by" => "Team.find_or_initialize_by(id: params[:id])",
      "the cbase form" => "::Team.find(params[:id])"
    }.each do |name, source|
      it "flags #{name}" do
        expect(offences_in(source).length).to eq(1), "#{source} was not flagged"
      end
    end
  end

  describe "what it allows" do
    it "allows the sanctioned boundary" do
      expect(offences_in("TenantScope.for(actor, Team).find(id)")).to be_empty
    end

    it "allows a lookup that is not by primary key" do
      expect(offences_in("Team.find_by(slug: slug)")).to be_empty
    end

    it "allows an association, which carries its own scope" do
      expect(offences_in("team.team_members.find_by(id: id)")).to be_empty
    end

    # A relation is not a lookup. `where(id: ids)` inside a scope or as a subquery
    # is how the boundary itself is written, and flagging it would push authors
    # towards suppressing the cop.
    it "allows `where(id:)` used as a relation rather than a lookup" do
      expect(offences_in("Team.where(id: ids)")).to be_empty
      expect(offences_in("Team.where(id: TeamMember.select(:team_id))")).to be_empty
    end

    it "allows a model that is not tenant-scoped" do
      expect(offences_in("User.find_by(id: id)")).to be_empty
      expect(offences_in("Session.find_by(id: id)")).to be_empty
    end
  end

  # The rule is only as good as its list. A model that belongs to a Team and is
  # missing here is a model the cop silently stops covering, which is exactly how
  # a check decays into decoration.
  describe "the models it knows are tenant-scoped" do
    it "covers every model that belongs to a Team" do
      # Without this the list is empty under lazy loading and the example passes
      # over nothing — the failure mode this whole file is about.
      Rails.application.eager_load!

      belonging = ApplicationRecord.descendants.select { |model|
        model.reflect_on_all_associations(:belongs_to).any? { |a| a.name == :team }
      }.map { |model| model.name.to_sym }

      expect(belonging).not_to be_empty, "no model belongs to a Team — the check found nothing to check"
      expect(described_class::TENANT_SCOPED).to include(*belonging)
    end

    it "names Team itself, which belongs to no Team but is the boundary" do
      expect(described_class::TENANT_SCOPED).to include(:Team)
    end
  end

  # And the cop is actually wired into the configuration the gate runs, not merely
  # defined. A cop that exists and is not required is a file.
  describe "its registration" do
    it "is required by .rubocop.yml" do
      expect(File.read(Rails.root.join(".rubocop.yml")))
        .to include("lib/rubocop/cop/opanel/unscoped_tenant_query.rb")
    end

    it "is enabled" do
      expect(File.read(Rails.root.join(".rubocop.yml")))
        .to match(/Opanel\/UnscopedTenantQuery:\s*\n\s*Enabled: true/)
    end
  end
end
