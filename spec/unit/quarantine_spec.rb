require "rails_helper"

# The quarantine policy of Annex D §20.1, made executable. A policy that lives
# only in a document decays; this one refuses the shapes it forbids.
RSpec.describe Quarantine, type: :unit do
  def metadata(quarantine, type: :integration)
    { quarantine: quarantine, type: type }
  end

  describe ".validate!" do
    it "accepts a quarantine with an owner, a deadline and a reason" do
      expect {
        described_class.validate!(metadata({ owner: "douglas", until: "2026-12-01", reason: "races with the sweep" }))
      }.not_to raise_error
    end

    %i[owner until reason].each do |key|
      it "refuses a quarantine missing #{key}" do
        details = { owner: "douglas", until: "2026-12-01", reason: "why" }.except(key)

        expect { described_class.validate!(metadata(details)) }
          .to raise_error(ArgumentError, /#{key}/)
      end
    end

    it "refuses a bare `true`, which would be a permanent skip" do
      expect { described_class.validate!(metadata(true)) }.to raise_error(ArgumentError, /Hash/)
    end

    it "refuses to quarantine a security example" do
      details = { owner: "douglas", until: "2026-12-01", reason: "intermittent" }

      expect { described_class.validate!(metadata(details, type: :security)) }
        .to raise_error(ArgumentError, /blocks release until it is understood/)
    end
  end

  describe ".expired?" do
    it "is false before the deadline" do
      expect(described_class.expired?(until: 1.week.from_now.to_date.to_s)).to be(false)
    end

    it "is true after it, so the example runs again and a still-flaky test goes red" do
      expect(described_class.expired?(until: 1.day.ago.to_date.to_s)).to be(true)
    end

    it "uses the controlled clock, so the deadline can be tested without waiting" do
      details = { until: "2026-10-01" }

      travel_to(Time.zone.parse("2026-09-30")) { expect(described_class.expired?(details)).to be(false) }
      travel_to(Time.zone.parse("2026-10-02")) { expect(described_class.expired?(details)).to be(true) }
    end
  end

  describe "the policy document" do
    it "states that retrying to green is not a fix" do
      policy = Rails.root.join("docs/engineering/flaky-tests.md").read

      expect(policy).to include("A flaky test is a defect")
      expect(policy).to match(/never resolved by retrying/)
      expect(policy).to match(/owner and a deadline/)
      expect(policy).to match(/may never be quarantined/)
    end
  end
end
