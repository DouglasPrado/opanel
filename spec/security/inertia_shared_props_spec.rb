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

  def shared_prop_keys
    get "/", headers: modern_browser

    payload = inertia_payload
    flatten_keys(payload.fetch("props").slice(*payload.fetch("sharedProps")))
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
