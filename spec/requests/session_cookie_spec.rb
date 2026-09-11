require "rails_helper"

# AC9 — the session cookie is `Secure`, `HttpOnly` and `SameSite` appropriate
# (Annex C §7.1). Both cookies are checked: the authentication cookie this Story
# adds, and Rails' own session cookie, which carries the CSRF token and the flash
# and is just as much a browser credential.
#
# `secure` is on in test as well, so what the assertion reads is the real
# attribute rather than a production-only branch nobody exercises.
RSpec.describe "the session cookie", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  def set_cookie_headers
    Array(response.headers["Set-Cookie"]).flat_map { |value| value.split("\n") }
  end

  def cookie_named(name)
    set_cookie_headers.find { |header| header.start_with?("#{name}=") }
  end

  # The integration cookie jar is Rack's, which holds the encoded value and has
  # no `signed` accessor. Rebuilding a request around the value is how the
  # application's own verifier — key generator, salt and serializer — is used to
  # read it, rather than a hand-rolled copy of it here.
  def signed_cookie(name)
    environment = Rack::MockRequest.env_for("/", "HTTP_COOKIE" => "#{name}=#{cookies[name]}")
      .merge(Rails.application.env_config)

    ActionDispatch::Request.new(environment).cookie_jar.signed[name]
  end

  before do
    https!
    post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
  end

  it "signs the user in, so the headers below are the ones a real login sets" do
    # M01-06 changed where authentication lands; this example is about the cookie
    # a real login sets, not about the destination.
    expect(response).to redirect_to(teams_path)
  end

  describe "the authentication cookie" do
    subject(:header) { cookie_named("opanel_session") }

    it "is set" do
      expect(header).to be_present
    end

    it "is HttpOnly, so no script can read it" do
      expect(header).to match(/;\s*HttpOnly/i)
    end

    it "is Secure, so it never travels in clear text" do
      expect(header).to match(/;\s*secure/i)
    end

    it "is SameSite=Lax — the post-login top-level GET must still carry it" do
      # Strict would drop the cookie on an inbound link and on the redirect that
      # follows sign-in. The state-changing requests are same-site and have been
      # CSRF-protected since M00-04.
      expect(header).to match(/;\s*SameSite=Lax/i)
    end

    it "is scoped to the whole application" do
      expect(header).to match(%r{;\s*path=/(;|\s|$)}i)
    end

    it "expires with the session's absolute lifetime" do
      expect(header).to match(/;\s*expires=/i)
    end
  end

  describe "Rails' own session cookie" do
    subject(:header) { cookie_named("_opanel_session") }

    it "is set" do
      expect(header).to be_present
    end

    it "carries the same three attributes" do
      expect(header).to match(/;\s*HttpOnly/i)
      expect(header).to match(/;\s*secure/i)
      expect(header).to match(/;\s*SameSite=Lax/i)
    end
  end

  describe "what the cookie contains — AC3" do
    it "is not the stored digest" do
      value = cookies[:opanel_session]
      digest = user.sessions.sole.token_digest

      expect(value).to be_present
      expect(value).not_to include(digest)
      expect(cookie_named("opanel_session")).not_to include(digest)
    end

    it "is signed, so a browser cannot forge one" do
      expect(signed_cookie("opanel_session")).to be_present
      expect(cookies[:opanel_session]).not_to eq(signed_cookie("opanel_session"))
    end

    it "holds a value that appears in no column of the sessions table" do
      raw = signed_cookie("opanel_session")

      expect(Session.sole.attributes.values.map(&:to_s)).not_to include(raw)
      expect(Session.where(token_digest: raw)).to be_empty
      expect(Session.sole.token_digest).to eq(Session.digest(raw))
    end

    it "holds a token with at least 256 bits of entropy" do
      expect(signed_cookie("opanel_session").length).to be >= 43
    end
  end

  it "clears the cookie on sign out" do
    delete sign_out_path, headers: modern_browser

    expect(cookie_named("opanel_session")).to match(/\Aopanel_session=;/)
  end
end
