require "rails_helper"

RSpec.describe "GET /", type: :request do
  it "boots the application and renders an HTML response" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("Opanel")
  end

  it "is not an API-only application" do
    expect(Rails.application.config.api_only).to be(false)
  end
end
