require "rails_helper"

# AC10 — "nenhum log contém senha, token bruto ou cookie, provado por teste".
#
# Every example asserts **both** halves: the event that should be there is
# there, and the three credentials are not. An assertion that only says "the
# buffer does not contain hunter2" passes just as happily over an empty buffer,
# which is the shape this check most easily degrades into.
RSpec.describe "authentication logging", type: :security do
  include RSpec::Rails::RequestExampleGroup

  let(:password) { "hunter2-hunter2-hunter2" }

  before { https! }

  # The raw session token, read back out of the signed cookie the response set.
  #
  # It is the only place the value exists after the request — the column holds
  # its SHA-256 — so an example that wants to prove the token is absent from the
  # log has to fetch it from here. The integration cookie jar is Rack's and has
  # no `signed` accessor, so a request is rebuilt around the value and the
  # application's own verifier reads it.
  def raw_session_token
    encoded = cookies[Authentication::COOKIE]
    return nil if encoded.blank?

    environment = Rack::MockRequest
      .env_for("/", "HTTP_COOKIE" => "#{Authentication::COOKIE}=#{encoded}")
      .merge(Rails.application.env_config)

    ActionDispatch::Request.new(environment).cookie_jar.signed[Authentication::COOKIE]
  end

  def credentials_absent_from(logs, raw_token: :none, cookie: nil)
    expect(logs).not_to include(password)

    # `:none` is the "this request created no session" case, and it is a
    # different statement from "the token happened to be blank". Passing a token
    # asserts it is real **before** asserting it is absent: guarding the
    # assertion with `if raw_token.present?` is how this clause came to never run
    # at all, and a nil token would have silently skipped it again.
    unless raw_token == :none
      expect(raw_token).to be_present, "no raw session token was captured, so nothing was proven absent"
      expect(raw_token.length).to be >= 43
      expect(Session.where(token_digest: Session.digest(raw_token))).to exist,
        "the captured value is not the token of a real session, so its absence proves nothing"

      expect(logs).not_to include(raw_token)
    end

    # `.present?`: a cleared cookie is the empty string, and `include("")` is true
    # of every string — an assertion that always passes is not one.
    expect(logs).not_to include(cookie) if cookie.present?
    expect(logs).not_to match(/"set-cookie"/i)
  end

  describe "registration" do
    it "records the event without the credential" do
      logs = capture_logs do
        post sign_up_path,
          params: { email: "new@example.test", password: password, display_name: "New" },
          headers: modern_browser
      end

      expect(logs).to include("auth.register.succeeded")
      # Registration signs the user in, so a raw token exists here too.
      credentials_absent_from(logs,
        raw_token: raw_session_token, cookie: response.headers["Set-Cookie"].to_s)
    end

    it "records a refusal by reason, never by address" do
      create(:user, email: "taken@example.test")

      logs = capture_logs do
        post sign_up_path,
          params: { email: "taken@example.test", password: password, display_name: "New" },
          headers: modern_browser
      end

      expect(logs).to include("auth.register.rejected")
      expect(logs).to include("email_unavailable")
      expect(logs).not_to include("taken@example.test")
      credentials_absent_from(logs)
    end
  end

  describe "login" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "records a success with the actor and the authentication context" do
      logs = capture_logs do
        post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      end

      expect(logs).to include("auth.login.succeeded")
      expect(logs).to include(Opanel::Identifier.external(:user, user.id))
      credentials_absent_from(logs,
        raw_token: raw_session_token, cookie: response.headers["Set-Cookie"].to_s)
    end

    it "writes the session token to no log line, under any key" do
      # The clause of AC10 that a helper guard used to skip entirely. Stated as
      # its own example so it cannot be lost inside a shared helper again, and
      # asserted against the whole buffer rather than against a named field:
      # AF-06 catches the field *name* `session_token`, and a leak is possible
      # under any other name.
      logs = capture_logs do
        post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      end

      token = raw_session_token

      expect(token).to be_present
      expect(Session.where(token_digest: Session.digest(token))).to exist
      expect(logs).to include("auth.login.succeeded")
      expect(logs).not_to include(token)
      # A prefix, too: a log that truncated the value would still be a leak of
      # most of it.
      expect(logs).not_to include(token[0, 16])
    end

    it "records a failure with one reason for every kind of failure" do
      logs = capture_logs do
        post sign_in_path, params: { email: user.email, password: "#{password}-wrong" },
          headers: modern_browser
      end

      expect(logs).to include("auth.login.failed")
      expect(logs).to include("invalid_credentials")
      expect(logs).not_to include("person@example.test")
      credentials_absent_from(logs)
    end

    it "records the throttle as an event an operator can alert on" do
      AuthenticationAttempt::LIMITS.fetch("login_email")[:threshold].times do
        AuthenticationAttempt.record(scope: "login_email", key: user.email)
      end

      logs = capture_logs do
        post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      end

      expect(logs).to include("auth.login.rate_limited")
      expect(logs).to include("login_email")
      credentials_absent_from(logs)
    end

    it "carries the request id, so a login can be tied to the request that made it" do
      logs = capture_logs do
        post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      end

      expect(logs).to include(response.headers["X-Request-Id"])
    end
  end

  describe "revocation" do
    let!(:user) { create(:user, email: "person@example.test", password: password) }

    it "records a sign-out" do
      post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      # Captured before the sign-out: the request that ends the session also
      # clears the cookie, so afterwards there is nothing left to read.
      token = raw_session_token
      encoded = cookies[:opanel_session]

      logs = capture_logs { delete sign_out_path, headers: modern_browser }

      expect(logs).to include("auth.session.revoked")
      credentials_absent_from(logs, raw_token: token, cookie: encoded)
    end

    it "records revoking another device" do
      post sign_in_path, params: { email: user.email, password: password }, headers: modern_browser
      other = create(:session, user: user)

      logs = capture_logs do
        delete account_session_path(Opanel::Identifier.external(:session, other.id)),
          headers: modern_browser
      end

      expect(logs).to include("auth.session.revoked")
      credentials_absent_from(logs,
        raw_token: raw_session_token, cookie: cookies[:opanel_session])
    end
  end

  describe "the sink itself" do
    it "redacts a credential written straight through Rails.logger" do
      # The control example. Redaction happens at the sink (Annex C §17.1)
      # precisely because the discipline above fails eventually, and this proves
      # the sink is doing its job rather than the buffer being empty.
      logs = capture_logs do
        Rails.logger.info(event: "probe", password: password, session_token: "probe-session-xyz789",
          cookie: "opanel_session=probe-token-abc123")
      end

      expect(logs).to include("probe")
      expect(logs).to include("[REDACTED]")
      expect(logs).not_to include(password)
      expect(logs).not_to include("probe-session-xyz789")
      expect(logs).not_to include("probe-token-abc123")
    end

    it "redacts a credential interpolated into free text" do
      logs = capture_logs { Rails.logger.warn("login attempt with password=#{password}") }

      expect(logs).to include("login attempt")
      expect(logs).not_to include(password)
    end
  end

  it "filters the credential out of Rails' own parameter logging" do
    # Asserted through the filter rather than by inspecting the configured list:
    # Rails compiles `filter_parameters` into a matcher, so a check on the shape
    # of the list would be a check on a Rails internal. What matters is what a
    # request's parameters look like by the time they reach the log.
    filtered = ActiveSupport::ParameterFilter
      .new(Rails.application.config.filter_parameters)
      .filter("password" => password, "email" => "person@example.test", "display_name" => "Person")

    expect(filtered["password"]).to eq("[FILTERED]")
    expect(filtered["email"]).to eq("[FILTERED]")
    expect(filtered["display_name"]).to eq("Person")
  end
end
