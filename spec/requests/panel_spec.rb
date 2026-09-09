require "rails_helper"

# AC1 and AC2 from the server's side, plus the tenancy rule the panel routes
# depend on: the Team slug in the path is an argument, never an authorization.
RSpec.describe "the panel", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let!(:team) { create(:team, owner: owner, name: "Acme", slug: "acme") }

  before { https! }

  # Errors render the way production renders them. Rails' developer page embeds
  # the failing query and the parameters, so a disclosure assertion against it
  # would be testing the debug screen rather than what a user is shown. Same
  # override as `spec/requests/csrf_and_errors_spec.rb`.
  around do |example|
    config = Rails.application.env_config
    previous = config.values_at("action_dispatch.show_exceptions",
      "action_dispatch.show_detailed_exceptions")
    config["action_dispatch.show_exceptions"] = :all
    config["action_dispatch.show_detailed_exceptions"] = false

    example.run
  ensure
    config["action_dispatch.show_exceptions"] = previous[0]
    config["action_dispatch.show_detailed_exceptions"] = previous[1]
  end

  def sign_in_as(user)
    post sign_in_path, params: { email: user.email, password: password }
  end

  describe "a signed-in member" do
    before { sign_in_as(owner) }

    it "reaches every section of doc 10 §3.2 that exists in M01" do
      %w[projects clusters audit settings].each do |section|
        get "/t/acme/#{section}"

        expect(response).to have_http_status(:ok), "#{section} answered #{response.status}"
      end
    end

    it "receives the shell's props on an authenticated page" do
      get "/t/acme/projects"

      props = inertia_props

      expect(props["currentUser"]).to include("name" => owner.display_name, "email" => owner.email)
      expect(props["teams"].map { |entry| entry["slug"] }).to include("acme")
      expect(props["currentTeam"]).to include("slug" => "acme")
    end

    # The shell needs the Team the URL names, not merely any Team the actor can
    # reach — otherwise switching Team would leave the header pointing at the
    # previous one.
    it "resolves the current Team from the path" do
      other = create(:team, owner: owner, name: "Beta", slug: "beta")

      get "/t/beta/projects"

      expect(inertia_props["currentTeam"]).to include("slug" => other.slug)
    end
  end

  describe "a member of another Team" do
    let(:outsider) { create(:user, email: "outsider@example.test", password: password) }
    let!(:outsider_team) { create(:team, owner: outsider, slug: "outsider-team") }

    before { sign_in_as(outsider) }

    # Annex C §7.3: absent, not forbidden. A 403 would confirm that `acme` exists.
    it "is answered as absent, not as forbidden" do
      get "/t/acme/projects"

      expect(response).to have_http_status(:not_found)
    end

    it "learns nothing about the Team it may not see" do
      get "/t/acme/projects"

      expect(response.body).not_to include("Acme")
    end
  end

  describe "an anonymous visitor" do
    it "is sent to sign in, not shown the shell" do
      get "/t/acme/projects"

      expect(response).to redirect_to(sign_in_path)
    end
  end

  describe "the pages that are deliberately outside the shell" do
    # The inventory's `app-shell` row says it is not for sign-in and other
    # standalone pages, and a shell around a sign-in form offers navigation the
    # visitor cannot use.
    it "publishes no identity on sign in" do
      get sign_in_path

      props = inertia_props

      expect(props).not_to have_key("currentUser")
      expect(props).not_to have_key("teams")
    end
  end
end
