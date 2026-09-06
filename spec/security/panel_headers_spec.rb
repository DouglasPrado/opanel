require "rails_helper"

# The panel's own security headers. They apply to the Control Plane and to nothing
# a user deploys: Opanel does not impose a content policy on a customer's
# workload (Annex C §14).
RSpec.describe "panel security headers", type: :request do
  let(:csp) { response.headers["Content-Security-Policy"].to_s }

  before { get "/", headers: modern_browser }

  it "sends a content security policy" do
    expect(csp).to be_present
  end

  {
    "default-src 'self'" => "restricts every fetch to the panel's own origin",
    "object-src 'none'" => "blocks plugin content outright",
    "frame-ancestors 'none'" => "prevents the panel from being framed",
    "base-uri 'self'" => "stops an injected <base> from redirecting relative URLs",
    "form-action 'self'" => "keeps a form from posting to another origin"
  }.each do |directive, reason|
    it "sets #{directive} — #{reason}" do
      expect(csp).to include(directive)
    end
  end

  it "does not weaken script-src outside development" do
    expect(Rails.env).to eq("test")
    expect(csp).not_to include("unsafe-eval")

    # Development allows an inline script for the React Refresh preamble. Nowhere
    # else may, and that is the directive an XSS actually needs.
    script_src = csp[/script-src([^;]*)/, 1].to_s
    expect(script_src).not_to include("unsafe-inline")
  end

  it "sends a referrer policy that does not leak panel paths" do
    expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "refuses MIME sniffing" do
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "denies device capabilities the panel never uses" do
    expect(response.headers["Permissions-Policy"]).to include("camera=()", "microphone=()", "geolocation=()")
  end

  it "leaves HSTS to force_ssl in production rather than sending it from a non-TLS environment" do
    expect(response.headers).not_to have_key("Strict-Transport-Security")
  end
end
