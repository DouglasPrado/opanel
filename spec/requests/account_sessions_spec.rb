require "rails_helper"

# AC5 — the user sees their devices with `lastSeenAt` and revokes one
# individually (doc 04 §8.2, "Session list").
RSpec.describe "the account session list", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  def sign_in
    post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
  end

  before do
    https!
    sign_in
  end

  describe "GET /settings/sessions" do
    it "renders the list as an Inertia page, with no REST endpoint behind it" do
      get account_sessions_path, headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_payload["component"]).to eq("Account/Sessions")
    end

    it "shows device metadata and lastSeenAt for each session" do
      create(:session, user: user, ip_address: "198.51.100.7", user_agent: "Firefox on Linux")

      get account_sessions_path, headers: modern_browser

      entry = inertia_props.fetch("sessions").find { |candidate| candidate["userAgent"] == "Firefox on Linux" }

      expect(entry).to be_present
      expect(entry["ipAddress"]).to eq("198.51.100.7")
      expect(entry["lastSeenAt"]).to be_present
      expect(entry["createdAt"]).to be_present
    end

    it "marks which entry is the session making the request" do
      create(:session, user: user)

      get account_sessions_path, headers: modern_browser

      current = inertia_props.fetch("sessions").select { |entry| entry["current"] }

      expect(current.length).to eq(1)
    end

    it "identifies each session by its prefixed identifier — ADR-0002 §2" do
      get account_sessions_path, headers: modern_browser

      expect(inertia_props.fetch("sessions").map { |entry| entry["id"] })
        .to all(match(/\Ases_[0-9A-HJKMNP-TV-Z]{26}\z/))
    end

    it "sends no token digest to the browser" do
      get account_sessions_path, headers: modern_browser

      expect(response.body).not_to include(user.sessions.first.token_digest)
      expect(inertia_props.fetch("sessions").flat_map(&:keys).uniq).not_to include("tokenDigest")
    end

    it "lists no other user's session" do
      other = create(:user)
      create(:session, user: other, user_agent: "Someone else's laptop")

      get account_sessions_path, headers: modern_browser

      expect(response.body).not_to include("Someone else's laptop")
    end

    it "refuses an anonymous visitor" do
      delete sign_out_path, headers: modern_browser

      get account_sessions_path, headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
    end
  end

  describe "DELETE /settings/sessions/:id" do
    it "revokes one session and leaves the others alone" do
      other = create(:session, user: user)

      delete account_session_path(Opanel::Identifier.external(:session, other.id)),
        headers: modern_browser

      expect(response).to redirect_to(account_sessions_path)
      expect(other.reload.revoked_at).to be_present
      expect(user.sessions.where(revoked_at: nil).count).to eq(1)
    end

    it "signs the user out when the revoked session is the current one" do
      current = user.sessions.sole

      delete account_session_path(Opanel::Identifier.external(:session, current.id)),
        headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
      expect(current.reload.revoked_at).to be_present

      get account_sessions_path, headers: modern_browser
      expect(response).to redirect_to(sign_in_path)
    end

    it "takes effect on the other device's very next request — AC4" do
      # A second browser, with its own cookie jar: this is the "revoked on
      # another device" case, and it has to fail on the next request rather than
      # on the next navigation.
      device = open_session
      device.https!
      device.post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser

      revoked = Session.order(:id).last
      device.get account_sessions_path, headers: modern_browser
      expect(device.response).to have_http_status(:ok)

      delete account_session_path(Opanel::Identifier.external(:session, revoked.id)),
        headers: modern_browser

      device.get account_sessions_path, headers: modern_browser

      expect(device.response).to have_http_status(:found)
      expect(device.response.headers["Location"]).to end_with(sign_in_path)
    end

    it "refuses another user's session without confirming it exists" do
      other = create(:session, user: create(:user))

      delete account_session_path(Opanel::Identifier.external(:session, other.id)),
        headers: modern_browser

      expect(response).to have_http_status(:not_found)
      expect(other.reload.revoked_at).to be_nil
    end

    it "refuses an anonymous caller" do
      other = create(:session, user: user)
      delete sign_out_path, headers: modern_browser

      delete account_session_path(Opanel::Identifier.external(:session, other.id)),
        headers: modern_browser

      expect(response).to redirect_to(sign_in_path)
      expect(other.reload.revoked_at).to be_nil
    end

    it "is idempotent" do
      other = create(:session, :revoked, user: user)
      first = other.reload.revoked_at

      delete account_session_path(Opanel::Identifier.external(:session, other.id)),
        headers: modern_browser

      expect(response).to redirect_to(account_sessions_path)
      expect(other.reload.revoked_at).to eq(first)
    end
  end
end
