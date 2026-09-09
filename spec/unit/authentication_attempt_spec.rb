require "rails_helper"

# The arithmetic of the throttle, under a frozen clock and without touching the
# database. The concurrent, real-PostgreSQL behaviour is
# spec/integration/login_rate_limit_spec.rb.
RSpec.describe AuthenticationAttempt, type: :unit do
  describe "LIMITS" do
    it "throttles login by address and by IP, and registration by IP" do
      expect(described_class::LIMITS.keys).to match_array(%w[login_email login_ip registration_ip])
    end

    it "gives every scope a threshold and a window" do
      described_class::LIMITS.each_value do |limit|
        expect(limit[:threshold]).to be_a(Integer).and be_positive
        expect(limit[:window]).to be_a(ActiveSupport::Duration)
      end
    end

    it "lets an address run out before the IP does, so one attacker cannot lock a whole office out" do
      expect(described_class::LIMITS.fetch("login_email")[:threshold])
        .to be < described_class::LIMITS.fetch("login_ip")[:threshold]
    end

    it "matches the scopes the CHECK constraint allows" do
      expect(described_class::SCOPES).to match_array(described_class::LIMITS.keys)
    end
  end

  describe ".digest" do
    it "stores a hash of the key, so the table is not a second copy of the address list" do
      # An enumerable table of the addresses that have ever tried to log in is a
      # disclosure by itself (Annex C §7.3).
      expect(described_class.digest("Person@Example.test")).to match(/\A[0-9a-f]{64}\z/)
      expect(described_class.digest("person@example.test"))
        .not_to include("person")
    end

    it "normalizes case and surrounding space before hashing" do
      expect(described_class.digest("  Person@Example.test ")).to eq(described_class.digest("person@example.test"))
    end
  end

  describe "#window_open?" do
    it "is open inside the window" do
      travel_to Time.utc(2026, 4, 1, 9, 0, 0) do
        attempt = described_class.new(scope: "login_email", window_started_at: 5.minutes.ago, attempt_count: 3)

        expect(attempt).to be_window_open
      end
    end

    it "has closed once the window has elapsed" do
      travel_to Time.utc(2026, 4, 1, 9, 0, 0) do
        attempt = described_class.new(scope: "login_email", window_started_at: 16.minutes.ago, attempt_count: 99)

        expect(attempt).not_to be_window_open
      end
    end
  end

  describe "#exceeded?" do
    def attempt(count, started: 1.minute.ago, scope: "login_email")
      described_class.new(scope: scope, window_started_at: started, attempt_count: count)
    end

    it "is false below the threshold" do
      travel_to Time.utc(2026, 4, 1, 9, 0, 0) do
        expect(attempt(described_class::LIMITS.fetch("login_email")[:threshold] - 1)).not_to be_exceeded
      end
    end

    it "is true at the threshold" do
      travel_to Time.utc(2026, 4, 1, 9, 0, 0) do
        expect(attempt(described_class::LIMITS.fetch("login_email")[:threshold])).to be_exceeded
      end
    end

    it "is false again once the window has closed, however high the count was" do
      travel_to Time.utc(2026, 4, 1, 9, 0, 0) do
        expect(attempt(1_000, started: 1.hour.ago)).not_to be_exceeded
      end
    end
  end
end
