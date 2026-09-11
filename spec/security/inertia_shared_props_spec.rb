require "rails_helper"

# Shared props are serialized into the HTML of every response. A token placed
# there is a token published to the browser, to the page cache and to any archived
# test artifact. This is the check that fails before that happens; AF-06 (M00-13)
# extends the same rule beyond this file.
RSpec.describe "Inertia shared props", type: :security do
  include RSpec::Rails::RequestExampleGroup

  # Substrings that mark a value as sensitive wherever it appears in a prop key.
  SENSITIVE_KEY_FRAGMENTS = %w[
    password secret token credential apikey api_key privatekey private_key
    passphrase recovery session cookie authorization signature encryption
  ].freeze

  def shared_prop_keys(path = "/")
    get path, headers: modern_browser

    payload = inertia_payload
    flatten_keys(payload.fetch("props").slice(*payload.fetch("sharedProps")))
  end

  # M01-06 added `currentUser`, `teams` and `currentTeam`, and they appear **only**
  # when somebody is signed in. Scanning `/` anonymously therefore scanned a
  # surface that does not include the props the rule is now mostly about — the
  # check ran where they do not exist. This signs in so the scan sees them.
  def signed_in_shared_prop_keys
    password = "hunter2-hunter2-hunter2"
    user = create(:user, email: "shared-props@example.test", password: password)
    create(:team, owner: user, slug: "shared-props-team")

    https!
    post sign_in_path, params: { email: user.email, password: password }

    shared_prop_keys("/t/shared-props-team/projects")
  end

  def flatten_keys(value, prefix = nil)
    case value
    when Hash
      value.flat_map do |key, nested|
        path = [ prefix, key ].compact.join(".")
        [ path, *flatten_keys(nested, path) ]
      end
    when Array
      value.flat_map { |nested| flatten_keys(nested, prefix) }
    else
      []
    end
  end

  it "declares which props are shared, so the surface is enumerable" do
    get "/", headers: modern_browser

    expect(inertia_payload["sharedProps"]).to match_array(%w[requestId flash errors])
  end

  it "declares the authenticated surface too, which is larger" do
    signed_in_shared_prop_keys

    expect(inertia_payload["sharedProps"])
      .to match_array(%w[requestId flash errors currentUser teams currentTeam])
  end

  it "contains no key marked as sensitive, signed in — where the props exist" do
    offending = signed_in_shared_prop_keys.select do |key|
      normalized = key.downcase.delete("_.")

      SENSITIVE_KEY_FRAGMENTS.any? { |fragment| normalized.include?(fragment.delete("_")) }
    end

    expect(offending).to be_empty,
      "these shared props look sensitive and are published in every authenticated response: #{offending.inspect}"
  end

  it "publishes no credential value, signed in" do
    keys = signed_in_shared_prop_keys
    body = response.body

    expect(keys).to include("currentUser.email"), "the scan did not reach the authenticated props"
    expect(body).not_to include("hunter2-hunter2-hunter2")
    expect(body).not_to match(/\$argon2id\$/)
    expect(body).not_to include(Session.last.token_digest) if Session.exists?
  end

  it "contains no key marked as sensitive" do
    offending = shared_prop_keys.select do |key|
      normalized = key.downcase.delete("_.")
      SENSITIVE_KEY_FRAGMENTS.any? { |fragment| normalized.include?(fragment.delete("_")) }
    end

    expect(offending).to be_empty,
      "shared props are published to the browser; remove #{offending.inspect}"
  end

  it "detects a sensitive key if one is ever added" do
    # The check has to be able to fail, or it proves nothing. This plants the
    # violation against the same matcher the real assertion uses.
    planted = flatten_keys("apiToken" => "value", "flash" => { "notice" => nil })

    offending = planted.select do |key|
      normalized = key.downcase.delete("_.")
      SENSITIVE_KEY_FRAGMENTS.any? { |fragment| normalized.include?(fragment.delete("_")) }
    end

    expect(offending).to eq([ "apiToken" ])
  end

  it "publishes no session or authorization value in the rendered document" do
    get "/", headers: modern_browser.merge("HTTP_AUTHORIZATION" => "Bearer probe-token-abc123")

    expect(response.body).not_to include("probe-token-abc123")
    expect(response.body).not_to include("Bearer ")
  end
end
