require "rails_helper"

RSpec.describe "authentication", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }

  # The session cookie is `Secure`, in test as well as in production (AC9), and
  # a secure cookie is not sent back over http. Driving the whole spec over TLS
  # is what lets the attribute be asserted for real instead of behind an
  # environment branch.
  before { https! }

  def sign_in(email:, secret: password)
    post sign_in_path, params: { email: email, password: secret }, headers: modern_browser
  end

  describe "signing up" do
    it "creates the account and signs the user in" do
      post sign_up_path,
        params: { email: "new@example.test", password: password, display_name: "New Person" },
        headers: modern_browser

      expect(response).to redirect_to(root_path)
      expect(User.sole.email).to eq("new@example.test")

      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "renders the sign-up page to an anonymous visitor" do
      get sign_up_path, headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_payload["component"]).to eq("Auth/SignUp")
    end

    it "re-renders the page with the refusal when the address is taken" do
      create(:user, email: "taken@example.test")

      post sign_up_path,
        params: { email: "taken@example.test", password: password, display_name: "Other" },
        headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props.dig("error", "code")).to eq("EMAIL_UNAVAILABLE")
    end

    it "never echoes the submitted credential back to the browser" do
      post sign_up_path,
        params: { email: "weak@example.test", password: "tinypw-9q7", display_name: "Weak" },
        headers: modern_browser

      expect(response.body).not_to include("tinypw-9q7")
    end
  end

  describe "signing in" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "renders the sign-in page to an anonymous visitor" do
      get sign_in_path, headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_payload["component"]).to eq("Auth/SignIn")
    end

    it "opens a session and sends the user on" do
      sign_in(email: "person@example.test")

      expect(response).to redirect_to(root_path)
      expect(user.sessions.count).to eq(1)
    end

    it "grants access to an authenticated page on the next request" do
      sign_in(email: "person@example.test")

      get account_sessions_path, headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_payload["component"]).to eq("Account/Sessions")
    end

    it "refuses a wrong password with the error envelope" do
      sign_in(email: "person@example.test", secret: "#{password}-wrong")

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props.dig("error", "code")).to eq("INVALID_CREDENTIALS")
      expect(user.sessions.count).to eq(0)
    end
  end

  describe "deny by default" do
    it "sends an anonymous visitor of an authenticated page to sign in" do
      get account_sessions_path, headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
    end

    it "preserves the destination and returns to it after signing in" do
      user = create(:user, email: "person@example.test", password: password)

      get account_sessions_path, headers: modern_browser
      sign_in(email: user.email)

      expect(response).to redirect_to(account_sessions_path)
    end

    it "does not treat a non-local destination as one to return to" do
      create(:user, email: "person@example.test", password: password)

      get sign_in_path, params: { return_to: "https://evil.test/steal" }, headers: modern_browser
      sign_in(email: "person@example.test")

      expect(response).to redirect_to(root_path)
    end

    it "requires every controller written after this Story to declare its access" do
      # The concern is included into ApplicationController and denies by default.
      # A new controller is authenticated unless it says otherwise, which is the
      # only ordering in which a forgotten declaration fails closed.
      expect(ApplicationController.ancestors).to include(Authentication)
      expect(ApplicationController._process_action_callbacks.map(&:filter))
        .to include(:require_authentication)
    end
  end

  describe "a revoked session — AC4" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "is rejected on the very next request, not on the next navigation" do
      sign_in(email: user.email)
      get account_sessions_path, headers: modern_browser
      expect(response).to have_http_status(:ok)

      # Revoked from another device. Nothing about the session is cached in the
      # cookie or in memory, so the next read of the row is the next request.
      user.sessions.sole.update!(revoked_at: Time.current)

      get account_sessions_path, headers: modern_browser
      expect(response).to redirect_to(sign_in_path)
    end

    it "is rejected on an Inertia XHR, not only on a full page visit" do
      sign_in(email: user.email)
      user.sessions.sole.update!(revoked_at: Time.current)

      get account_sessions_path, headers: modern_browser.merge(
        "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest
      )

      expect(response).to have_http_status(:found).or have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with(sign_in_path)
    end

    it "clears the cookie it refused, so the browser stops sending it" do
      sign_in(email: user.email)
      user.sessions.sole.update!(revoked_at: Time.current)

      get account_sessions_path, headers: modern_browser

      expect(response.headers["Set-Cookie"].to_s).to match(/opanel_session=;/)
    end
  end

  describe "expiry — AC8" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "rejects a request once the absolute lifetime has passed" do
      travel_to Time.utc(2026, 7, 1, 9, 0, 0) do
        sign_in(email: user.email)
      end

      travel_to Time.utc(2026, 7, 1, 9, 0, 0) + Session::ABSOLUTE_TTL + 1.minute do
        get account_sessions_path, headers: modern_browser

        expect(response).to redirect_to(sign_in_path)
      end
    end

    it "keeps a session usable for its whole absolute lifetime while it is being used" do
      start = Time.utc(2026, 7, 1, 9, 0, 0)
      travel_to(start) { sign_in(email: user.email) }

      # Used every six hours, so the idle window never closes. The session must
      # survive right up to the absolute expiry and not one moment past it.
      (6.hours..(Session::ABSOLUTE_TTL - 1.hour)).step(6.hours) do |offset|
        travel_to start + offset do
          get account_sessions_path, headers: modern_browser

          expect(response).to have_http_status(:ok), "rejected #{offset / 3600} hours in"
        end
      end

      travel_to start + Session::ABSOLUTE_TTL + 1.second do
        get account_sessions_path, headers: modern_browser

        expect(response).to redirect_to(sign_in_path)
      end
    end

    it "rejects a request after the idle window, even well inside the absolute lifetime" do
      travel_to Time.utc(2026, 7, 1, 9, 0, 0) do
        sign_in(email: user.email)
      end

      travel_to Time.utc(2026, 7, 1, 9, 0, 0) + Session::IDLE_TTL + 2.minutes do
        get account_sessions_path, headers: modern_browser

        expect(response).to redirect_to(sign_in_path)
      end
    end

    it "refreshes last_seen_at as the session is used, so activity extends the idle window" do
      start = Time.utc(2026, 7, 1, 9, 0, 0)
      travel_to(start) { sign_in(email: user.email) }

      travel_to start + Session::IDLE_TTL - 1.hour do
        get account_sessions_path, headers: modern_browser
        expect(response).to have_http_status(:ok)
      end

      travel_to start + Session::IDLE_TTL + 1.hour do
        get account_sessions_path, headers: modern_browser

        expect(response).to have_http_status(:ok)
      end
    end

    it "does not extend the absolute expiry when it refreshes last_seen_at" do
      start = Time.utc(2026, 7, 1, 9, 0, 0)
      travel_to(start) { sign_in(email: user.email) }
      expires_at = user.sessions.sole.expires_at

      travel_to start + 1.day do
        get account_sessions_path, headers: modern_browser
      end

      expect(user.sessions.sole.expires_at).to eq(expires_at)
    end

    it "throttles the last_seen_at write rather than paying for one per request" do
      travel_to Time.utc(2026, 7, 1, 9, 0, 0) do
        sign_in(email: user.email)
        before = user.sessions.sole.last_seen_at

        get account_sessions_path, headers: modern_browser

        expect(user.sessions.sole.last_seen_at).to eq(before)
      end
    end
  end

  describe "signing out" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "revokes the session server-side rather than only dropping the cookie" do
      sign_in(email: user.email)

      delete sign_out_path, headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
      expect(user.sessions.sole.revoked_at).to be_present
    end

    it "leaves the user unauthenticated afterwards" do
      sign_in(email: user.email)
      delete sign_out_path, headers: modern_browser

      get account_sessions_path, headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
    end
  end
end
