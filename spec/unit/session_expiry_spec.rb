require "rails_helper"

# AC8 — absolute **and** idle expiry, proven with a controlled clock. Annex C
# §7.1 requires both; a session that only expires on inactivity never ends for a
# user who keeps a tab open, and one that only expires absolutely stays usable
# on an abandoned laptop for its whole lifetime.
#
# No `sleep` anywhere: `spec/support/clock.rb` already provides travel_to.
RSpec.describe Session, type: :unit do
  # Built, never saved: this is about the predicate, not about persistence.
  def session(expires_in: Session::ABSOLUTE_TTL, idle_for: 0.seconds, revoked: false)
    build(:session,
      expires_at: expires_in.from_now,
      last_seen_at: idle_for.ago,
      revoked_at: revoked ? Time.current : nil)
  end

  describe "the two lifetimes" do
    it "declares an absolute TTL and a shorter idle TTL" do
      expect(Session::ABSOLUTE_TTL).to eq(7.days)
      expect(Session::IDLE_TTL).to eq(12.hours)
      expect(Session::IDLE_TTL).to be < Session::ABSOLUTE_TTL
    end
  end

  describe "#active?" do
    it "is active when it is fresh, unexpired and not revoked" do
      expect(session).to be_active
    end

    it "stops being active at the absolute expiry, however recently it was used" do
      travel_to Time.utc(2026, 3, 1, 12, 0, 0) do
        record = session(expires_in: 1.hour)

        travel 59.minutes
        record.last_seen_at = Time.current
        expect(record).to be_active

        travel 2.minutes
        record.last_seen_at = Time.current
        expect(record).not_to be_active
      end
    end

    it "stops being active after the idle window, however far the absolute expiry is" do
      travel_to Time.utc(2026, 3, 1, 12, 0, 0) do
        record = session(expires_in: 7.days)

        travel Session::IDLE_TTL - 1.minute
        expect(record).to be_active

        travel 2.minutes
        expect(record).not_to be_active
      end
    end

    it "is inactive the moment it is revoked, whatever the clock says" do
      expect(session(revoked: true)).not_to be_active
    end

    it "is inactive at exactly the absolute expiry, not one tick after" do
      travel_to Time.utc(2026, 3, 1, 12, 0, 0) do
        record = build(:session, expires_at: Time.current, last_seen_at: Time.current)

        expect(record).not_to be_active
      end
    end
  end

  describe "#expires_at" do
    it "is never extended by use — that is what makes it absolute" do
      expect(Session.new).not_to respond_to(:extend_expiry!)
      expect(Session.instance_methods).not_to include(:renew!)
    end
  end

  describe ".digest" do
    it "is a hex SHA-256 of the raw token" do
      expect(Session.digest("a-token")).to eq(OpenSSL::Digest::SHA256.hexdigest("a-token"))
      expect(Session.digest("a-token")).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is stable, so a cookie can be looked up by one indexed read" do
      expect(Session.digest("a-token")).to eq(Session.digest("a-token"))
    end

    it "differs for different tokens" do
      expect(Session.digest("a-token")).not_to eq(Session.digest("b-token"))
    end
  end

  describe "#stale_last_seen?" do
    it "throttles the write, so idle expiry is accurate to within the throttle" do
      travel_to Time.utc(2026, 3, 1, 12, 0, 0) do
        record = session

        expect(record).not_to be_stale_last_seen

        travel Session::LAST_SEEN_THROTTLE + 1.second
        expect(record).to be_stale_last_seen
      end
    end

    it "keeps the throttle far below the idle window" do
      expect(Session::LAST_SEEN_THROTTLE).to be < Session::IDLE_TTL
    end
  end
end
