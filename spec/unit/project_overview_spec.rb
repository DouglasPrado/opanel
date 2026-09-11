require "rails_helper"

# The minimal `ProjectOverview` of doc 09 §23.
#
# This file exists because the independent review proved the Query was not
# covered: replacing the body of `#call` with `raise` left 1140 examples green.
# A class that can be made to always raise without a single test noticing is not
# tested — it is merely present.
RSpec.describe ProjectOverview, :integration do
  let(:team) { create(:team, name: "Acme", slug: "acme") }
  let(:owner) { team.owner }
  let(:project) { create(:project, team: team, name: "Billing", slug: "billing") }

  def member(role)
    user = create(:user)
    create(:team_member, team: team, user: user, role: role, status: "ACTIVE")
    user
  end

  describe "the resource it describes" do
    it "carries the Project as the interface addresses it" do
      overview = described_class.call(actor: owner, project: project)

      expect(overview.id).to eq(project.external_id)
      expect(overview.name).to eq("Billing")
      expect(overview.slug).to eq("billing")
      expect(overview.status).to eq("ACTIVE")
    end

    # External identifiers, never bare ULIDs. A page that rendered the raw column
    # would put an identifier in a URL that `Opanel::Identifier.parse` then
    # refuses.
    it "renders identifiers in their external form" do
      overview = described_class.call(actor: owner, project: project)

      expect(overview.id).to match(/\Aprj_/)
      expect(overview.team.id).to match(/\Ateam_/)
    end

    it "names the Team the Project belongs to" do
      overview = described_class.call(actor: owner, project: project)

      expect(overview.team.name).to eq("Acme")
      expect(overview.team.slug).to eq("acme")
    end

    it "carries a description when there is one, and nil when there is not" do
      expect(described_class.call(actor: owner, project: project).description).to be_nil

      project.update!(description: "Invoices and dunning.")

      expect(described_class.call(actor: owner, project: project.reload).description)
        .to eq("Invoices and dunning.")
    end
  end

  # The half that makes this a composition rather than a wrapper: the screen
  # needs to know which Project *and* what this actor may do to it, and asking
  # the Policy once per button is how a page ends up offering an action the
  # server refuses.
  describe "the permissions it resolves" do
    it "gives an OWNER both" do
      overview = described_class.call(actor: owner, project: project)

      expect(overview.permissions.update).to be(true)
      expect(overview.permissions.archive).to be(true)
    end

    it "gives an ADMIN both" do
      overview = described_class.call(actor: member("ADMIN"), project: project)

      expect(overview.permissions).to have_attributes(update: true, archive: true)
    end

    # doc 04 §6.2 plus the Story's *"arquivar exige ADMIN"*: a DEVELOPER may
    # rename and may not archive. This is the row that would silently widen if the
    # Policy were ever copied instead of referenced.
    it "lets a DEVELOPER rename and not archive" do
      overview = described_class.call(actor: member("DEVELOPER"), project: project)

      expect(overview.permissions).to have_attributes(update: true, archive: false)
    end

    it "gives a VIEWER neither" do
      overview = described_class.call(actor: member("VIEWER"), project: project)

      expect(overview.permissions).to have_attributes(update: false, archive: false)
    end

    # Deny by default reaches the read model too. An actor who somehow arrives
    # here without a membership — the tenancy boundary should have stopped them
    # first — must not be offered a single action.
    it "gives an actor with no membership neither" do
      overview = described_class.call(actor: create(:user), project: project)

      expect(overview.permissions).to have_attributes(update: false, archive: false)
    end

    it "reads the decision from ProjectPolicy rather than from the role directly" do
      actor = member("ADMIN")

      expect(ProjectPolicy).to receive(:new).with(actor, project).and_call_original

      described_class.call(actor: actor, project: project)
    end
  end
end
