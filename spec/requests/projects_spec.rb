require "rails_helper"

# The Projects section end to end: AC1, AC3, AC4, AC7, AC8 and the error envelope
# the Story's API Impact requires — *"slug duplicado retorna erro de validação
# inline, não 500"*.
RSpec.describe "projects", type: :request do
  let(:password) { "hunter2-hunter2-hunter2" }
  let(:owner) { create(:user, email: "owner@example.test", password: password) }
  let!(:team) { create(:team, owner: owner, name: "Acme", slug: "acme") }

  before { https! }

  # Errors render the way production renders them; Rails' developer page embeds
  # the failing query and the parameters, so a disclosure assertion against it
  # would be testing the debug screen. Same override as `spec/requests/panel_spec.rb`.
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

  def member(role, of: team)
    user = create(:user, password: password)
    create(:team_member, team: of, user: user, role: role, status: "ACTIVE")
    user
  end

  describe "creating one (AC1)" do
    before { sign_in_as(owner) }

    # UC-009 passo 6: *"UI abre Project Overview"*. Not the list — the use case
    # this Story cites is explicit, and going back to the list was the divergence
    # that left `ProjectOverview` with no caller.
    it "creates the Project and opens its overview" do
      expect { post "/t/acme/projects", params: { name: "Billing Ops" } }
        .to change { team.projects.count }.by(1)

      project = team.projects.last
      expect(response).to redirect_to("/t/acme/projects/#{project.external_id}")
      expect(project).to have_attributes(name: "Billing Ops", slug: "billing-ops",
        status: "ACTIVE")
    end

    it "records the creation in the audit trail (AC8)" do
      expect { post "/t/acme/projects", params: { name: "Billing Ops" } }
        .to change { AuditLog.where(action: "project.created").count }.by(1)

      record = AuditLog.where(action: "project.created").last
      expect(record.team_id).to eq(team.id)
      expect(record.actor_id).to eq(owner.id)
      expect(record.result).to eq("SUCCESS")
      expect(record.after).to include("name" => "Billing Ops", "slug" => "billing-ops")
      # The correlation fields M01-05 requires; without them the trail cannot be
      # walked back to the request that produced it.
      expect(record.request_id).to be_present
    end

    it "accepts an explicit slug" do
      post "/t/acme/projects", params: { name: "Billing Ops", slug: "billing" }

      expect(team.projects.last.slug).to eq("billing")
    end

    # The Story's failure table, and the API Impact: inline validation, never a
    # 500, and the form is not lost — the page comes back with the list intact.
    it "answers a duplicate slug with an inline validation error and a suggestion" do
      create(:project, team: team, slug: "billing")

      post "/t/acme/projects", params: { name: "Billing", slug: "billing" }

      expect(response).to have_http_status(:unprocessable_content)

      props = inertia_props
      expect(props["error"]).to include("code" => "VALIDATION_ERROR")
      expect(props["error"]["message"]).to eq(CreateProject::SLUG_TAKEN)
      expect(props["suggestion"]).to eq("billing-2")
      # The list is still there: the form is re-rendered, not replaced by an
      # error page.
      expect(props["projects"].length).to eq(1)
    end

    it "answers a blank name with a validation error rather than a database error" do
      post "/t/acme/projects", params: { name: "   " }

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props["error"]["message"]).to eq(CreateProject::NAME_REQUIRED)
    end

    it "answers a name with nothing sluggable by asking for a usable one" do
      post "/t/acme/projects", params: { name: "!!!" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props["error"]["message"]).to eq(CreateProject::SLUG_UNUSABLE)
    end

    # AC3, through the HTTP surface: uniqueness is per Team.
    it "allows the same slug in a different Team" do
      other_owner = create(:user, password: password)
      other = create(:team, owner: other_owner, slug: "beta")
      create(:project, team: other, slug: "billing")

      expect { post "/t/acme/projects", params: { name: "Billing", slug: "billing" } }
        .to change { team.projects.count }.by(1)

      expect(response).to redirect_to("/t/acme/projects/#{team.projects.last.external_id}")
    end
  end

  describe "listing them" do
    before { sign_in_as(owner) }

    it "shows only this Team's Projects, with the permissions the actor has" do
      create(:project, team: team, name: "Ours", slug: "ours")
      create(:project, team: create(:team), name: "Theirs", slug: "theirs")

      get "/t/acme/projects"

      props = inertia_props
      expect(props["projects"].map { |p| p["slug"] }).to eq([ "ours" ])
      expect(props["permissions"]).to eq({ "create" => true })
    end

    it "offers a cursor while there is more to show" do
      create_list(:project, ProjectsForTeam::DEFAULT_LIMIT + 1, team: team)

      get "/t/acme/projects"

      expect(inertia_props["nextCursor"]).to match(/\Aprj_/)
    end

    it "continues from the cursor" do
      create_list(:project, ProjectsForTeam::DEFAULT_LIMIT + 1, team: team)
      get "/t/acme/projects"
      cursor = inertia_props["nextCursor"]

      get "/t/acme/projects", params: { cursor: cursor }

      expect(inertia_props["projects"].length).to eq(1)
      expect(inertia_props["nextCursor"]).to be_nil
    end

    it "does not offer creation to a VIEWER" do
      sign_in_as(member("VIEWER"))

      get "/t/acme/projects"

      expect(inertia_props["permissions"]).to eq({ "create" => false })
    end
  end

  # The read UC-009 step 6 lands on, and the one caller `ProjectOverview` has.
  # Until round 2 of the review this route did not exist and the Query was dead
  # code — proved by replacing its body with `raise` and watching the whole suite
  # stay green.
  describe "reading one" do
    let!(:project) do
      create(:project, team: team, name: "Billing", slug: "billing", description: "Invoices.")
    end

    it "renders the overview with the Project and its Team" do
      sign_in_as(owner)

      get "/t/acme/projects/#{project.external_id}"

      props = inertia_props
      expect(props["project"]).to include("name" => "Billing", "slug" => "billing",
        "status" => "ACTIVE", "description" => "Invoices.")
      expect(props["team"]).to include("slug" => "acme")
    end

    it "offers an OWNER both actions" do
      sign_in_as(owner)

      get "/t/acme/projects/#{project.external_id}"

      expect(inertia_props["permissions"]).to eq({ "update" => true, "archive" => true })
    end

    # The UI must not offer an action the server refuses. A DEVELOPER renames and
    # does not archive (doc 04 §6.2 plus the Story's "arquivar exige ADMIN").
    it "offers a DEVELOPER the rename and not the archive" do
      sign_in_as(member("DEVELOPER"))

      get "/t/acme/projects/#{project.external_id}"

      expect(inertia_props["permissions"]).to eq({ "update" => true, "archive" => false })
    end

    it "offers a VIEWER neither" do
      sign_in_as(member("VIEWER"))

      get "/t/acme/projects/#{project.external_id}"

      expect(inertia_props["permissions"]).to eq({ "update" => false, "archive" => false })
    end

    it "answers a Project of another Team as absent" do
      sign_in_as(owner)
      theirs = create(:project, team: create(:team))

      get "/t/acme/projects/#{theirs.external_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(theirs.name)
    end

    it "answers a malformed identifier identically" do
      sign_in_as(owner)

      get "/t/acme/projects/not-an-id"

      expect(response).to have_http_status(:not_found)
    end

    it "does not reach it signed out" do
      get "/t/acme/projects/#{project.external_id}"

      expect(response).to redirect_to(sign_in_path)
    end
  end

  describe "renaming one (AC7)" do
    let!(:project) { create(:project, team: team, name: "Billing", slug: "billing") }

    before { sign_in_as(owner) }

    it "changes the slug, and nothing points at the old one" do
      patch "/t/acme/projects/#{project.external_id}", params: { slug: "invoicing" }

      expect(response).to redirect_to("/t/acme/projects/#{project.external_id}")
      expect(project.reload.slug).to eq("invoicing")
      # The identity did not move: the ULID is what every reference uses.
      expect(project.reload.id).to eq(project.id)
    end

    it "records the change in the audit trail, with before and after (AC8)" do
      expect { patch "/t/acme/projects/#{project.external_id}", params: { name: "Invoicing" } }
        .to change { AuditLog.where(action: "project.updated").count }.by(1)

      record = AuditLog.where(action: "project.updated").last
      expect(record.before).to eq({ "name" => "Billing" })
      expect(record.after).to eq({ "name" => "Invoicing" })
    end

    it "leaves a field the request did not send alone" do
      project.update!(description: "Kept")

      patch "/t/acme/projects/#{project.external_id}", params: { name: "Invoicing" }

      expect(project.reload.description).to eq("Kept")
    end

    it "clears a description the request sent empty" do
      project.update!(description: "Kept")

      patch "/t/acme/projects/#{project.external_id}", params: { description: "" }

      expect(project.reload.description).to be_nil
    end

    it "answers a taken slug inline rather than with a 500" do
      create(:project, team: team, slug: "invoicing")

      patch "/t/acme/projects/#{project.external_id}", params: { slug: "invoicing" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(inertia_props["error"]["message"]).to eq(UpdateProject::SLUG_TAKEN)
    end

    it "accepts a rename to the slug it already has" do
      patch "/t/acme/projects/#{project.external_id}", params: { slug: "billing" }

      expect(response).to redirect_to("/t/acme/projects/#{project.external_id}")
    end
  end

  describe "archiving one" do
    let!(:project) { create(:project, team: team, slug: "billing") }

    it "archives for an ADMIN" do
      sign_in_as(member("ADMIN"))

      post "/t/acme/projects/#{project.external_id}/archive"

      expect(project.reload.status).to eq("ARCHIVED")
    end

    it "refuses a DEVELOPER, who may create but not archive" do
      sign_in_as(member("DEVELOPER"))

      post "/t/acme/projects/#{project.external_id}/archive"

      expect(response).to have_http_status(:forbidden)
      expect(project.reload.status).to eq("ACTIVE")
    end

    # The refusal is a page, not a crash, and it discloses nothing. Until this
    # Story nothing raised `Authorization::Denied` and a role refusal came back
    # as a 500 — the request spec is what found it.
    it "renders the refusal without leaking why, or anything internal" do
      sign_in_as(member("DEVELOPER"))

      post "/t/acme/projects/#{project.external_id}/archive"

      props = inertia_props
      expect(props["status"]).to eq(403)
      expect(props["message"]).to eq(ErrorsController::STATUS_MESSAGES.fetch(403))
      # The reason distinguishes "your role does not permit this" from "you have
      # no membership"; showing it would turn a refusal into an oracle.
      expect(response.body).not_to include("insufficient_role")
      expect(response.body).not_to include("ArchiveProject")
      expect(response.body).not_to match(%r{/Users/|/app/controllers})
      # What support actually needs survives.
      expect(props["requestId"]).to be_present
    end

    it "answers an already-archived Project with a conflict, not a 500" do
      sign_in_as(owner)
      project.update!(status: "ARCHIVED")

      post "/t/acme/projects/#{project.external_id}/archive"

      expect(response).to have_http_status(:conflict)
      expect(inertia_props["error"]["message"]).to eq(ArchiveProject::ALREADY_ARCHIVED)
    end
  end

  # AC4 through the routes, which is where a tenancy mistake actually reaches a
  # user. NOT_FOUND and FORBIDDEN must be indistinguishable across Teams, or the
  # difference is an existence oracle (Annex C §7.3).
  describe "cross-team (AC4)" do
    let(:outsider) { create(:user, password: password) }
    let!(:their_team) { create(:team, owner: outsider, slug: "beta") }
    let!(:project) { create(:project, team: team, slug: "billing") }

    before { sign_in_as(outsider) }

    it "answers 404 for the list of a Team the actor does not belong to" do
      get "/t/acme/projects"

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 when renaming another Team's Project through their own path" do
      patch "/t/beta/projects/#{project.external_id}", params: { name: "Renamed" }

      expect(response).to have_http_status(:not_found)
      expect(project.reload.name).not_to eq("Renamed")
    end

    it "answers 404 when archiving another Team's Project" do
      post "/t/beta/projects/#{project.external_id}/archive"

      expect(response).to have_http_status(:not_found)
      expect(project.reload.status).to eq("ACTIVE")
    end

    # The same answer a Project that never existed gets. Different statuses here
    # would tell an enumerator which identifiers are real.
    it "answers a Project that does not exist identically" do
      post "/t/beta/projects/prj_#{Opanel::Identifier.generate}/archive"

      expect(response).to have_http_status(:not_found)
    end

    it "answers a malformed identifier identically, rather than with a 500" do
      post "/t/beta/projects/not-an-id/archive"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "signed out" do
    it "does not reach the list" do
      get "/t/acme/projects"

      expect(response).to redirect_to(sign_in_path)
    end

    it "does not create" do
      expect { post "/t/acme/projects", params: { name: "Billing" } }
        .not_to change(Project, :count)
    end
  end
end
