require "rails_helper"

# AC6: no audit record contains a secret, a token, a password or a key — proved
# with values planted through the real code paths, not by inspecting the
# sanitiser in isolation.
#
# The distinction matters. A unit test of the allowlist proves the allowlist; this
# proves the *system*, including the fields somebody passes to `AuditTrail.record`
# without thinking, and the ones an attribute hash carries along for free.
RSpec.describe "what never reaches an audit record", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }

  def register(email)
    RegisterUser.call(email: email, display_name: "Somebody", password: password,
      ip: "203.0.113.7", user_agent: "rspec")
  end

  # Everything written to the trail, as one string. If a value is anywhere in
  # here — in a column, in `before`, in `after` — this finds it.
  def everything_written
    AuditLog.all.map { |entry| entry.attributes.to_json }.join("\n")
  end

  describe "after the identity flows of this Milestone" do
    before do
      registration = register("first@example.test")
      AuthenticateUser.call(email: "first@example.test", password: password,
        ip: "203.0.113.7", user_agent: "rspec")
      RevokeSession.call(actor: registration.value[:user],
        session_id: registration.value[:session].external_id)
    end

    it "wrote something, so the assertions below are not passing over an empty table" do
      expect(AuditLog.count).to be >= 4
    end

    it "contains no password" do
      expect(everything_written).not_to include(password)
    end

    it "contains no password digest" do
      digest = User.find_by(email: "first@example.test").password_digest

      expect(digest).to start_with("$argon2id$")
      expect(everything_written).not_to include(digest)
      expect(everything_written).not_to include("argon2id")
    end

    it "contains no session token digest" do
      Session.pluck(:token_digest).each do |token_digest|
        expect(everything_written).not_to include(token_digest)
      end
    end

    it "contains no raw session token" do
      raw = register("second@example.test").value[:session_token]

      expect(raw.length).to be >= 43
      expect(everything_written).not_to include(raw)
    end
  end

  # The planted-value case the Story asks for: a caller hands the trail a payload
  # containing exactly what must never be stored.
  describe "a sensitive value planted in before/after" do
    let!(:registration) { register("planted@example.test") }
    let(:team) { Team.first }

    it "records that it changed and not what it was" do
      AuditTrail.record(
        action: :team_created, actor: registration.value[:user], resource: team,
        before: { "name" => "Old", "password" => "PLANTED-SECRET-VALUE" },
        after: { "name" => "New", "token_digest" => "PLANTED-DIGEST-VALUE" }
      )

      entry = AuditLog.where(action: AuditLog::ACTIONS[:team_created]).last

      expect(entry.before["password"]).to eq(AuditSanitizer::MASK)
      expect(entry.after["token_digest"]).to eq(AuditSanitizer::MASK)
      expect(entry.attributes.to_json).not_to include("PLANTED-SECRET-VALUE")
      expect(entry.attributes.to_json).not_to include("PLANTED-DIGEST-VALUE")
    end

    it "drops a field nobody allowed, rather than storing it" do
      AuditTrail.record(
        action: :team_created, actor: registration.value[:user], resource: team,
        after: { "name" => "Kept", "unreviewed_field" => "PLANTED-UNKNOWN-VALUE" }
      )

      entry = AuditLog.where(action: AuditLog::ACTIONS[:team_created]).last

      expect(entry.after).to eq({ "name" => "Kept" })
      expect(entry.attributes.to_json).not_to include("PLANTED-UNKNOWN-VALUE")
    end

    # The whole attribute hash of a model is the most common thing a caller
    # passes, and the one most likely to carry something it should not.
    it "drops the sensitive columns of a whole attribute hash" do
      user = registration.value[:user]

      AuditTrail.record(action: :user_registered, actor: user, resource: user,
        after: user.attributes)

      entry = AuditLog.where(action: AuditLog::ACTIONS[:user_registered]).last

      expect(entry.after.keys).to all(be_in(AuditSanitizer::ALLOWED["User"] + AuditSanitizer::SENSITIVE))
      expect(entry.after["password_digest"]).to eq(AuditSanitizer::MASK)
      expect(entry.attributes.to_json).not_to include(user.password_digest)
    end
  end

  # The control: the assertions above must be able to fail. If the allowlist were
  # removed, a planted value would land in the row — and this shows the search
  # would find it.
  describe "the search itself" do
    it "would find a planted value if one were stored" do
      register("control@example.test")
      entry = AuditLog.first

      expect(entry.attributes.to_json).to include(entry.request_id)
      expect(everything_written).to include(AuditLog::ACTIONS[:user_registered])
    end
  end
end
