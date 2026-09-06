require "rails_helper"

RSpec.describe "component gallery", type: :request do
  let(:modern_browser) do
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36" }
  end

  it "renders the Gallery Inertia page" do
    get "/gallery", headers: modern_browser

    expect(response).to have_http_status(:ok)

    payload = JSON.parse(CGI.unescapeHTML(response.body[/data-page="([^"]*)"/, 1]))
    expect(payload["component"]).to eq("Gallery")
  end

  it "is a development tool, so the route does not exist in production" do
    # The route is drawn conditionally; asserting the condition itself keeps the
    # check honest without booting a second environment.
    source = Rails.root.join("config/routes.rb").read

    expect(source).to match(/gallery.*if Rails\.env\.development\? \|\| Rails\.env\.test\?/)
  end
end
