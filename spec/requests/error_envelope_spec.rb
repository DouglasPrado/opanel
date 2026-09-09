require "rails_helper"

# doc 09 §28 — a stable error model: `code`, `message`, `requestId`. It is used
# from this Story on, so the first delivery channel does not invent a second
# shape that everything after has to be translated into.
RSpec.describe "the error envelope", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  before { https! }

  def envelope = inertia_props["error"]

  describe "a failed sign-in" do
    before do
      post sign_in_path, params: { email: user.email, password: "#{password}-wrong" },
        headers: modern_browser
    end

    it "carries a stable code" do
      expect(envelope["code"]).to eq("INVALID_CREDENTIALS")
    end

    it "carries a message a person can act on" do
      expect(envelope["message"]).to be_present
      expect(envelope["message"]).to be_a(String)
    end

    it "carries the request id, and it is the one in the response header" do
      expect(envelope["requestId"]).to be_present
      expect(envelope["requestId"]).to eq(response.headers["X-Request-Id"])
    end

    it "answers 422, so a client can branch on the status as well as the code" do
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "leaks nothing internal" do
      expect(envelope.keys).to match_array(%w[code message requestId])
      expect(response.body).not_to include("SELECT")
      expect(response.body).not_to include("argon2")
      expect(response.body).not_to match(%r{app/commands/})
    end
  end

  describe "a throttled sign-in" do
    it "answers 429 with RATE_LIMITED" do
      AuthenticationAttempt::LIMITS.fetch("login_email")[:threshold].times do
        AuthenticationAttempt.record(scope: "login_email", key: user.email)
      end

      post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser

      expect(response).to have_http_status(:too_many_requests)
      expect(envelope["code"]).to eq("RATE_LIMITED")
      expect(envelope["requestId"]).to eq(response.headers["X-Request-Id"])
    end
  end

  describe "a session identifier of the wrong type" do
    it "answers VALIDATION_ERROR with 422, never NOT_FOUND — ADR-0002 §4" do
      session = create(:session, user: user)
      post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser

      delete account_session_path(Opanel::Identifier.external(:user, session.id)),
        headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(envelope["code"]).to eq("VALIDATION_ERROR")
    end

    it "answers NOT_FOUND for a well-formed identifier the caller does not own" do
      other = create(:session, user: create(:user))
      post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser

      delete account_session_path(Opanel::Identifier.external(:session, other.id)),
        headers: modern_browser

      expect(response).to have_http_status(:not_found)
      expect(envelope["code"]).to eq("NOT_FOUND")
      expect(other.reload.revoked_at).to be_nil
    end
  end

  describe "a failed sign-up" do
    it "states the password rule that was broken without echoing the value" do
      post sign_up_path,
        params: { email: "new@example.test", password: "tinypw-9q7", display_name: "New" },
        headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(envelope["code"]).to eq("VALIDATION_ERROR")
      expect(envelope["message"]).to match(/12 characters/)
      expect(response.body).not_to include("tinypw-9q7")
    end
  end
end
