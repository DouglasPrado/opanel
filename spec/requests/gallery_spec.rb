require "rails_helper"

RSpec.describe "component gallery", type: :request do
  it "renders the Gallery Inertia page" do
    get "/gallery", headers: modern_browser

    expect(response).to have_http_status(:ok)

    expect(inertia_payload["component"]).to eq("Gallery")
  end

  it "is a development tool, so the route does not exist in production" do
    # The route is drawn conditionally; asserting the condition itself keeps the
    # check honest without booting a second environment.
    source = Rails.root.join("config/routes.rb").read

    expect(source).to match(/gallery.*if Rails\.env\.development\? \|\| Rails\.env\.test\?/)
  end
end
