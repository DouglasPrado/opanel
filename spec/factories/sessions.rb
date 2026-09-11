FactoryBot.define do
  # The raw token is a transient: what the row carries is its SHA-256 digest, and
  # an example that needs the value the browser would hold asks for it
  # explicitly. No fixture stores a usable session credential.
  factory :session do
    user

    transient do
      session_token { SecureRandom.urlsafe_base64(32) }
    end

    token_digest { Session.digest(session_token) }
    expires_at { Session::ABSOLUTE_TTL.from_now }
    last_seen_at { Time.current }
    ip_address { "203.0.113.10" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end

    trait :idle do
      last_seen_at { (Session::IDLE_TTL + 1.minute).ago }
    end
  end
end
