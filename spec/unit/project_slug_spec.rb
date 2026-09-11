require "rails_helper"

# Slug generation and validation (AC7, doc 09 §19).
RSpec.describe Project, ".slugify and .suggest_slug" do
  describe ".slugify" do
    it "derives a URL segment from a name" do
      expect(described_class.slugify("Billing Ops")).to eq("billing-ops")
    end

    it "collapses runs of punctuation into a single hyphen" do
      expect(described_class.slugify("Billing   &&  Ops!!")).to eq("billing-ops")
    end

    it "drops leading and trailing separators rather than emitting an invalid slug" do
      expect(described_class.slugify("  --Billing--  ")).to eq("billing")
    end

    it "truncates to the length the CHECK accepts, without ending on a hyphen" do
      slug = described_class.slugify("#{'a' * 62} b")

      expect(slug.length).to be <= described_class::SLUG_MAX_LENGTH
      expect(slug).to match(described_class::SLUG_FORMAT)
    end

    # Total, and nil rather than a guess: a name with nothing usable in it has to
    # make the caller decide, not persist something the CHECK will reject.
    it "answers nil when nothing usable remains" do
      expect(described_class.slugify("!!!")).to be_nil
      expect(described_class.slugify("")).to be_nil
    end

    it "answers nil for a single character, which is below the minimum" do
      expect(described_class.slugify("a")).to be_nil
    end

    # Reuse, asserted rather than assumed: the two slugs answer to the same CHECK
    # and the same alphabet, so a correction to one must reach the other.
    it "is the same function Team uses" do
      %w[Billing\ Ops --x-- !!! a].each do |value|
        expect(described_class.slugify(value)).to eq(Team.slugify(value))
      end
    end
  end

  describe ".suggest_slug" do
    let(:team) { create(:team) }

    it "offers the next free variant" do
      create(:project, team: team, slug: "billing")

      expect(described_class.suggest_slug(team: team, taken: "billing")).to eq("billing-2")
    end

    it "skips variants that are themselves taken" do
      create(:project, team: team, slug: "billing")
      create(:project, team: team, slug: "billing-2")

      expect(described_class.suggest_slug(team: team, taken: "billing")).to eq("billing-3")
    end

    # A Project renaming itself must not be told its own slug is in the way.
    it "ignores the Project being renamed" do
      project = create(:project, team: team, slug: "billing-2")
      create(:project, team: team, slug: "billing")

      expect(described_class.suggest_slug(team: team, taken: "billing", excluding: project.id))
        .to eq("billing-2")
    end

    it "does not consider another Team's slugs taken" do
      create(:project, team: create(:team), slug: "billing")
      create(:project, team: team, slug: "billing")

      expect(described_class.suggest_slug(team: team, taken: "billing")).to eq("billing-2")
    end

    # The bound is what keeps a popular name from turning creation into a scan.
    # Past it the suggestion is random, and it still has to be a valid slug.
    it "falls back to entropy once the probes are exhausted" do
      (2..described_class::SUGGESTION_ATTEMPTS).each do |number|
        create(:project, team: team, slug: "billing-#{number}")
      end

      suggestion = described_class.suggest_slug(team: team, taken: "billing")

      expect(suggestion).to match(described_class::SLUG_FORMAT)
      expect(suggestion).not_to match(/\Abilling-\d\z/)
    end

    it "keeps the suggestion inside the length the CHECK accepts" do
      long = "a" * described_class::SLUG_MAX_LENGTH

      expect(described_class.suggest_slug(team: team, taken: long).length)
        .to be <= described_class::SLUG_MAX_LENGTH
    end
  end
end
