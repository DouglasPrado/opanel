require "rails_helper"

# Probe controllers exist only for this spec. They are routed in, exercised and
# routed back out, so what is under test is ApplicationController's real
# configuration rather than a stub of it — and no probe route reaches production.
class CsrfProbeController < ApplicationController
  def create
    head :ok
  end
end

class BoomProbeController < ApplicationController
  def show
    raise "probe failure with an internal detail: SELECT * FROM secrets"
  end
end

RSpec.describe "CSRF protection and error rendering", type: :request do
  let(:modern_browser) do
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36" }
  end

  def inertia_payload(body)
    raw = body[/data-page="([^"]*)"/, 1]
    raise "response is not an Inertia page: #{body[0, 200]}" if raw.nil?

    JSON.parse(CGI.unescapeHTML(raw))
  end

  # Error responses are rendered the way production renders them: ShowExceptions
  # handles the failure and Rails' developer page is off. The middleware reads
  # both per request, so they can be overridden here without rebuilding the stack.
  around do |example|
    Rails.application.routes.draw do
      post "/__probe/csrf" => "csrf_probe#create"
      get "/__probe/boom" => "boom_probe#show"
      root "home#show"
    end

    config = Rails.application.env_config
    previous = config.values_at("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.show_detailed_exceptions"] = false

    example.run
  ensure
    config["action_dispatch.show_exceptions"] = previous[0]
    config["action_dispatch.show_detailed_exceptions"] = previous[1]
    Rails.application.reload_routes!
  end

  describe "CSRF" do
    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    it "rejects a state-changing request without a valid token" do
      post "/__probe/csrf", headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_payload(response.body)["component"]).to eq("Error")
    end

    it "accepts the same request when the token is present" do
      get "/", headers: modern_browser
      token = response.body[/name="csrf-token" content="([^"]+)"/, 1]

      expect(token).to be_present

      post "/__probe/csrf", headers: modern_browser.merge("X-CSRF-Token" => token)

      expect(response).to have_http_status(:ok)
    end

    it "raises rather than silently dropping the session" do
      expect(ApplicationController.forgery_protection_strategy)
        .to eq(ActionController::RequestForgeryProtection::ProtectionMethods::Exception)
    end
  end

  describe "server errors" do
    it "renders an Inertia error page instead of Rails' static HTML" do
      get "/__probe/boom", headers: modern_browser

      expect(response).to have_http_status(:internal_server_error)
      expect(inertia_payload(response.body)["component"]).to eq("Error")
    end

    it "shows the request id so the failure can be found in the server log" do
      get "/__probe/boom", headers: modern_browser

      props = inertia_payload(response.body).fetch("props")

      expect(props["requestId"]).to be_present
      expect(props["status"]).to eq(500)
    end

    it "leaks no stack trace, SQL or internal path to the user" do
      get "/__probe/boom", headers: modern_browser

      expect(response.body).not_to include("SELECT * FROM secrets")
      expect(response.body).not_to include("probe failure")
      expect(response.body).not_to match(%r{/app/controllers/})
      expect(response.body).not_to include("boom_probe.rb")
    end

    it "renders a missing page as a 404 rather than a blank response" do
      get "/__probe/does-not-exist", headers: modern_browser

      expect(response).to have_http_status(:not_found)
      expect(inertia_payload(response.body).dig("props", "status")).to eq(404)
    end
  end
end
