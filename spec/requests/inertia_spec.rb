require "rails_helper"

RSpec.describe "Inertia rendering", type: :request do
  describe "GET /" do
    it "renders an Inertia page backed by a React component" do
      get "/", headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")

      payload = inertia_payload
      expect(payload["component"]).to eq("Home")
      expect(payload["url"]).to eq("/")
    end

    it "sends the page its server-driven props" do
      get "/", headers: modern_browser

      props = inertia_payload.fetch("props")

      expect(props.dig("platform", "name")).to eq("Opanel")
      expect(props.dig("platform", "environment")).to eq("test")
    end

    it "answers an Inertia XHR visit with JSON rather than a full document" do
      get "/", headers: modern_browser.merge(
        "X-Inertia" => "true",
        "X-Inertia-Version" => ViteRuby.digest
      )

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["component"]).to eq("Home")
    end

    it "references the digested Vite assets" do
      get "/", headers: modern_browser

      expect(response.body).to match(%r{<script src="/vite[^"]*/assets/application-[A-Za-z0-9_-]+\.js"})
    end

    it "serves no REST endpoint built only to feed the UI" do
      json_only_routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
        .grep(%r{\A/api/})

      expect(json_only_routes).to be_empty,
        "the UI is served by Inertia; a REST route exists for MCP, the CLI and automation, not for this tree"
    end
  end

  describe "shared props" do
    it "carries the request id so a browser action can be found in the server log" do
      get "/", headers: modern_browser

      props = inertia_payload.fetch("props")

      expect(props["requestId"]).to be_present
      expect(props["requestId"]).to eq(response.headers["X-Request-Id"])
    end

    it "exposes flash as a structured prop rather than a rendered partial" do
      get "/", headers: modern_browser

      expect(inertia_payload.dig("props", "flash")).to eq(
        "notice" => nil, "alert" => nil
      )
    end
  end
end
