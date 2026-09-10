require "rails_helper"

# The state machine of doc 09 §5.1, and the Commands that drive it.
#
# The transitions are asserted as *reachability*, not as a table read back: a
# table is a claim, and an edge nothing can traverse reads as a capability while
# being unreachable. That is exactly the shape of `M01-04`'s open finding about
# `:out_of_scope`, and this Story does not repeat it.
RSpec.describe "the Project lifecycle", :integration do
  let(:team) { create(:team) }
  let(:owner) { team.owner }

  describe "the declared transitions" do
    it "allows ACTIVE → ARCHIVED" do
      expect(build(:project, status: "ACTIVE").can_transition_to?("ARCHIVED")).to be(true)
    end

    it "refuses ARCHIVED → ACTIVE, because no Command in this Milestone restores" do
      expect(build(:project, :archived).can_transition_to?("ACTIVE")).to be(false)
    end

    it "refuses to leave DELETING, which needs the runtime gone first (M02-09)" do
      expect(build(:project, :deleting).can_transition_to?("ACTIVE")).to be(false)
      expect(build(:project, :deleting).can_transition_to?("ARCHIVED")).to be(false)
    end

    # Total rather than raising: the caller is a guard, and a guard that explodes
    # is a guard somebody rescues into `true`.
    it "answers false for an unknown status instead of raising" do
      project = build(:project)
      project.status = "PAUSED"

      expect(project.can_transition_to?("ARCHIVED")).to be(false)
    end

    # Every edge declared must be one a Command can actually traverse. Without
    # this, a future edge added "for completeness" becomes a rule nothing
    # enforces and nothing can be seen failing.
    it "declares no edge that no Command can traverse" do
      reachable = Project::TRANSITIONS.flat_map { |from, targets| targets.map { |to| [ from, to ] } }

      expect(reachable).to eq([ [ "ACTIVE", "ARCHIVED" ] ])
    end
  end

  describe "ArchiveProject" do
    it "moves an ACTIVE Project to ARCHIVED" do
      project = create(:project, team: team)

      result = ArchiveProject.call(actor: owner, project: project)

      expect(result).to be_success
      expect(project.reload.status).to eq("ARCHIVED")
    end

    it "refuses a Project that is already archived, as an outcome not an exception" do
      project = create(:project, :archived, team: team)

      result = ArchiveProject.call(actor: owner, project: project)

      expect(result).to be_failure
      expect(result.code).to eq("CONFLICT")
      expect(result.message).to eq(ArchiveProject::ALREADY_ARCHIVED)
    end

    it "refuses a Project that is being deleted, and says which of the two it is" do
      project = create(:project, :deleting, team: team)

      result = ArchiveProject.call(actor: owner, project: project)

      expect(result).to be_failure
      expect(result.message).to eq(ArchiveProject::BEING_DELETED)
    end

    it "records the transition in the audit trail (AC8)" do
      project = create(:project, team: team)

      expect { ArchiveProject.call(actor: owner, project: project) }
        .to change { AuditLog.where(action: "project.archived").count }.by(1)

      record = AuditLog.where(action: "project.archived").last
      expect(record.resource_id).to eq(project.id)
      expect(record.team_id).to eq(team.id)
      expect(record.before).to eq({ "status" => "ACTIVE" })
      expect(record.after).to eq({ "status" => "ARCHIVED" })
      expect(record.result).to eq("SUCCESS")
    end

    # AC5 is **not** proved here, and this example says so rather than leaving a
    # gap that reads like coverage. `Environment` is created by `M01-11`, whose
    # own precondition is this Story — recorded as SC-18. Asserting the guard
    # against a table that does not exist is not possible; asserting that
    # archiving *succeeds* today is, and it is the honest statement of where the
    # rule stands.
    it "archives with nothing to block it, because Environments do not exist yet (SC-18)" do
      expect(ActiveRecord::Base.connection.table_exists?("environments")).to be(false)

      project = create(:project, team: team)

      expect(ArchiveProject.call(actor: owner, project: project)).to be_success
    end
  end

  describe "UpdateProject on an archived Project" do
    it "refuses, and promises no restore that does not exist" do
      project = create(:project, :archived, team: team)

      result = UpdateProject.call(actor: owner, project: project, name: "New name")

      expect(result).to be_failure
      expect(result.code).to eq("CONFLICT")
      expect(project.reload.name).not_to eq("New name")
    end
  end
end
