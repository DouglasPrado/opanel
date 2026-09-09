require "rails_helper"

# AC6 — "login com e-mail inexistente e login com senha errada são
# indistinguíveis na resposta" (doc 10 UC-001, Annex C §7.1).
#
# The comparison is a **diff of the whole response**, normalized only for the
# CSRF token and the request id, which vary per request by design. Asserting
# only that both say INVALID_CREDENTIALS would pass over two bodies that differ
# in any other way — and one of them would be the oracle.
RSpec.describe "login response indistinguishability", type: :security do
  include RSpec::Rails::RequestExampleGroup

  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  before { https! }

  def attempt(email:, secret:)
    post sign_in_path, params: { email: email, password: secret }, headers: modern_browser

    {
      status: response.status,
      location: response.headers["Location"],
      content_type: response.media_type,
      body: normalize(response.body)
    }
  end

  # Only what is *supposed* to differ between two requests.
  def normalize(body)
    body
      .gsub(/name="csrf-token" content="[^"]+"/, 'name="csrf-token" content="TOKEN"')
      .gsub(/&quot;[A-Za-z0-9-]{36}&quot;/, "&quot;REQUEST_ID&quot;")
      .gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, "REQUEST_ID")
  end

  def unknown_address = attempt(email: "nobody@example.test", secret: password)
  def wrong_password = attempt(email: user.email, secret: "#{password}-wrong")

  it "answers an unknown address and a wrong password with the identical response" do
    expect(wrong_password).to eq(unknown_address)
  end

  it "answers with the same status" do
    expect(wrong_password[:status]).to eq(unknown_address[:status])
    expect(wrong_password[:status]).to eq(422)
  end

  it "sets the same Location header — which is to say, neither sets one" do
    expect(wrong_password[:location]).to eq(unknown_address[:location])
  end

  it "carries the same error code and message" do
    unknown = unknown_address
    wrong = wrong_password

    expect(inertia_props.dig("error", "code")).to eq("INVALID_CREDENTIALS")
    expect(unknown[:body]).to eq(wrong[:body])
  end

  it "answers a SUSPENDED account the same way" do
    user.update!(status: "SUSPENDED")

    expect(attempt(email: user.email, secret: password)).to eq(unknown_address)
  end

  it "answers a DELETED_PENDING account the same way" do
    user.update!(status: "DELETED_PENDING")

    expect(attempt(email: user.email, secret: password)).to eq(unknown_address)
  end

  it "performs one Argon2 verification on both paths" do
    # Without this, an early return for an unknown address is a timing oracle
    # even when the bodies are byte-identical. `verify_dummy` runs the same KDF
    # against a constant digest, so the not-found branch cannot be optimized
    # back into a cheap `return`.
    allow(Opanel::PasswordHashing).to receive(:verify).and_call_original

    unknown_address
    expect(Opanel::PasswordHashing).to have_received(:verify).once

    wrong_password
    expect(Opanel::PasswordHashing).to have_received(:verify).twice
  end

  it "would notice a divergence, so the comparison is not vacuous" do
    # The diff has to be able to fail. Two responses that genuinely differ must
    # not compare equal under the normalization above.
    expect(unknown_address).not_to eq(attempt(email: user.email, secret: password))
  end

  it "reveals nothing in the log either" do
    # A log that records "unknown user" while the response says "invalid
    # credentials" moves the oracle rather than removing it.
    logs = capture_logs { unknown_address }
    other = capture_logs { wrong_password }

    reason = ->(text) { text.scan(/"reason":"([^"]+)"/).flatten }

    expect(reason.call(logs)).to eq(reason.call(other))
    expect(logs).not_to include("nobody@example.test")
    expect(logs).not_to match(/unknown[_ ]user|no such|not registered/i)
  end
end
