require "rails_helper"

# AC1 and AC7 through a real request, and the cross-team negative that every new
# mutation owes (AGENT_RULES, "Testing").
RSpec.describe "teams", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "founder@example.test", password: password) }

  def sign_in(as: user)
    post sign_in_path, params: { email: as.email, password: password }, headers: modern_browser
  end

  before do
    https!
    sign_in
  end

  describe "POST /teams" do
    it "creates the Team and makes the caller its OWNER (AC1)" do
      post teams_path, params: { name: "Acme Industries" }, headers: modern_browser

      team = Team.sole
      expect(team).to have_attributes(name: "Acme Industries", slug: "acme-industries",
        owner_user_id: user.id, status: "ACTIVE")
      expect(team.team_members.sole).to have_attributes(user_id: user.id, role: "OWNER", status: "ACTIVE")
      expect(response).to redirect_to(team_path(team.external_id))
    end

    it "records the membership as joined, so the audit trail has a date" do
      post teams_path, params: { name: "Acme" }, headers: modern_browser

      expect(TeamMember.sole.joined_at).to be_within(5.seconds).of(Time.current)
    end

    it "accepts an explicit URL name" do
      post teams_path, params: { name: "Acme Industries", slug: "acme" }, headers: modern_browser

      expect(Team.sole.slug).to eq("acme")
    end

    it "refuses a duplicate slug inline and suggests a free one (AC7)" do
      create(:team, slug: "acme")

      post teams_path, params: { name: "Acme", slug: "acme" }, headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_payload["component"]).to eq("Teams/Index")
      expect(inertia_props["error"]).to include("code" => "VALIDATION_ERROR")
      expect(inertia_props["suggestion"]).to eq("acme-2")
      expect(Team.where(slug: "acme").count).to eq(1)
    end

    it "refuses a name that cannot become a URL name" do
      post teams_path, params: { name: "///" }, headers: modern_browser

      expect(response).to have_http_status(:unprocessable_content)
      expect(Team.count).to eq(0)
    end

    it "refuses an anonymous caller" do
      delete sign_out_path, headers: modern_browser

      post teams_path, params: { name: "Acme" }, headers: modern_browser

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with(sign_in_path)
      expect(Team.count).to eq(0)
    end

    it "leaks no internal detail when the slug is refused" do
      create(:team, slug: "acme")

      post teams_path, params: { name: "Acme", slug: "acme" }, headers: modern_browser

      expect(response.body).not_to include("index_teams_unique_slug_when_not_deleted")
      expect(response.body).not_to include("PG::")
    end
  end

  describe "GET /teams" do
    it "lists only the Teams the caller is an active member of" do
      mine = create(:team, name: "Mine", owner: user)
      create(:team, name: "Somebody else's")

      get teams_path, headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_payload["component"]).to eq("Teams/Index")
      expect(inertia_props["teams"].map { |team| team["id"] }).to eq([ mine.external_id ])
      expect(inertia_props["teams"].sole["role"]).to eq("OWNER")
    end
  end

  describe "GET /teams/:id" do
    it "renders a Team the caller belongs to" do
      team = create(:team, owner: user)

      get team_path(team.external_id), headers: modern_browser

      expect(response).to have_http_status(:ok)
      expect(inertia_props.dig("team", "id")).to eq(team.external_id)
    end

    it "answers 404, not 403, for another team's Team" do
      other = create(:team)

      get team_path(other.external_id), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for a malformed identifier, without saying which shapes are real" do
      get team_path("not-an-identifier"), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for an identifier of another type" do
      team = create(:team, owner: user)

      get team_path(Opanel::Identifier.external(:user, team.id)), headers: modern_browser

      expect(response).to have_http_status(:not_found)
    end
  end
end
