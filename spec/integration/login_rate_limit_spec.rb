require "rails_helper"

# AC7 — the throttle blocks repeated attempts, proven by a test, with no sleep.
#
# The mechanism is a PostgreSQL row, not the Rails cache: `cache_store` is
# `:null_store` in test, so `ActionController::RateLimiting` — which skips the
# limit when the store returns nil — would be silently inert exactly here, and
# an evictable limiter is one an attacker can flush.
RSpec.describe "login rate limiting", type: :integration do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  let(:email_threshold) { AuthenticationAttempt::LIMITS.fetch("login_email")[:threshold] }
  let(:ip_threshold) { AuthenticationAttempt::LIMITS.fetch("login_ip")[:threshold] }
  let(:window) { AuthenticationAttempt::LIMITS.fetch("login_email")[:window] }

  def attempt(email: "person@example.test", secret: "#{password}-wrong", ip: "203.0.113.5")
    AuthenticateUser.call(email: email, password: secret, ip: ip, user_agent: "RSpec")
  end

  it "refuses further attempts on the address once the threshold is reached" do
    email_threshold.times { expect(attempt.code).to eq("INVALID_CREDENTIALS") }

    result = attempt

    expect(result.code).to eq("RATE_LIMITED")
    expect(result.message).to be_present
  end

  it "refuses the correct password too, once the address is throttled" do
    # Otherwise the throttle is a hint: "keep going, that one was different".
    email_threshold.times { attempt }

    expect(attempt(secret: password).code).to eq("RATE_LIMITED")
    expect(Session.count).to eq(0)
  end

  it "counts an unknown address exactly like a known one" do
    # If only known addresses were counted, the throttle would answer the
    # question the response refuses to answer (AC6).
    email_threshold.times { attempt(email: "nobody@example.test") }

    expect(attempt(email: "nobody@example.test").code).to eq("RATE_LIMITED")
  end

  it "lets the address through again once the window has passed" do
    email_threshold.times { attempt }
    expect(attempt.code).to eq("RATE_LIMITED")

    travel(window + 1.minute) do
      expect(attempt(secret: password)).to be_success
    end
  end

  it "clears the address counter on a successful login" do
    (email_threshold - 1).times { attempt }

    expect(attempt(secret: password)).to be_success

    (email_threshold - 1).times { expect(attempt.code).to eq("INVALID_CREDENTIALS") }
  end

  it "throttles one address without throttling another from the same IP" do
    create(:user, email: "second@example.test", password: password)

    email_threshold.times { attempt }

    expect(attempt.code).to eq("RATE_LIMITED")
    expect(attempt(email: "second@example.test", secret: password)).to be_success
  end

  it "throttles the IP once enough distinct addresses have been tried from it" do
    # Spraying a different address every time never trips the per-address limit,
    # which is why the second scope exists. The first attempts are recorded
    # directly so the example is about the threshold rather than about paying for
    # thirty Argon2 verifications.
    (ip_threshold - 1).times { AuthenticationAttempt.record(scope: "login_ip", key: "203.0.113.5") }
    expect(attempt(email: "spray@example.test").code).to eq("INVALID_CREDENTIALS")

    expect(attempt(email: "person@example.test", secret: password).code).to eq("RATE_LIMITED")
  end

  it "does not throttle a different IP" do
    ip_threshold.times { AuthenticationAttempt.record(scope: "login_ip", key: "203.0.113.5") }

    expect(attempt(secret: password, ip: "198.51.100.9")).to be_success
  end

  describe "the counter row" do
    it "stores only a hash of the key, never the address" do
      attempt

      rows = AuthenticationAttempt.all

      expect(rows).not_to be_empty
      expect(rows.map(&:key_digest)).to all(match(/\A[0-9a-f]{64}\z/))
      expect(rows.map(&:attributes).to_s).not_to include("person@example.test")
    end

    it "counts in one statement, so two racing writers cannot both read three" do
      # ON CONFLICT ... DO UPDATE is atomic; a read-then-write would need a lock
      # that a login path cannot afford to take.
      5.times { AuthenticationAttempt.record(scope: "login_email", key: "person@example.test") }

      row = AuthenticationAttempt.find_by(
        scope: "login_email", key_digest: AuthenticationAttempt.digest("person@example.test")
      )

      expect(row.attempt_count).to eq(5)
    end

    it "restarts the count rather than accumulating across windows" do
      travel_to Time.utc(2026, 6, 1, 8, 0, 0) do
        3.times { AuthenticationAttempt.record(scope: "login_email", key: "person@example.test") }
      end

      travel_to Time.utc(2026, 6, 1, 8, 0, 0) + window + 1.minute do
        count = AuthenticationAttempt.record(scope: "login_email", key: "person@example.test")

        expect(count).to eq(1)
      end
    end

    it "keeps one row per scope and key" do
      3.times { AuthenticationAttempt.record(scope: "login_ip", key: "203.0.113.5") }

      expect(AuthenticationAttempt.where(scope: "login_ip").count).to eq(1)
    end

    it "refuses an unknown scope at the database" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO authentication_attempts
            (id, scope, key_digest, window_started_at, attempt_count, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', 'password_reset', '#{'a' * 64}', now(), 1, now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /authentication_attempts_scope/)
    end

    it "sweeps rows whose window closed long ago" do
      travel_to Time.utc(2026, 6, 1, 8, 0, 0) do
        AuthenticationAttempt.record(scope: "login_email", key: "person@example.test")
      end

      travel_to Time.utc(2026, 6, 3, 8, 0, 0) do
        expect { AuthenticationAttempt.sweep }.to change(AuthenticationAttempt, :count).to(0)
      end
    end

    it "does not sweep a row still inside its window" do
      AuthenticationAttempt.record(scope: "login_email", key: "person@example.test")

      expect { AuthenticationAttempt.sweep }.not_to change(AuthenticationAttempt, :count)
    end
  end

  describe "registration" do
    it "throttles account creation per IP, which is what makes open sign-up survivable" do
      limit = AuthenticationAttempt::LIMITS.fetch("registration_ip")[:threshold]

      limit.times do |index|
        RegisterUser.call(email: "new-#{index}@example.test", password: password,
          display_name: "New", ip: "203.0.113.9", user_agent: "RSpec")
      end

      result = RegisterUser.call(email: "one-too-many@example.test", password: password,
        display_name: "New", ip: "203.0.113.9", user_agent: "RSpec")

      expect(result.code).to eq("RATE_LIMITED")
      expect(User.where(email: "one-too-many@example.test")).to be_empty
    end
  end
end
