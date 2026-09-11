require "rails_helper"

# The permission matrix of doc 04 §6.2 as it applies to a Project (AC9), and the
# cross-team denial that AC4 requires for all three mutations.
RSpec.describe "Project authorization", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }

  # A member of `team` holding `role`. Built through the membership rather than
  # by stubbing a Policy: what is being tested is the decision the application
  # actually makes, and a stub would pass with the rule deleted.
  def member(role)
    user = create(:user)
    create(:team_member, team: team, user: user, role: role, status: "ACTIVE")
    user
  end

  ROLES = %w[OWNER ADMIN DEVELOPER VIEWER].freeze

  describe "the matrix" do
    # doc 04 §6.2, row "Criar Project/Environment": everybody but VIEWER.
    # Creating is decided by `TeamPolicy`, because there is no Project yet to
    # scope the decision to.
    describe "create" do
      { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false }.each do |role, allowed|
        it "#{allowed ? 'permits' : 'refuses'} a #{role}" do
          actor = role == "OWNER" ? team.owner : member(role)

          expect(TeamPolicy.new(actor, team).create_project?).to be(allowed)
        end
      end
    end

    # Renaming carries the same roles as creating: it changes a name in a URL and
    # nothing about who may reach the Project.
    describe "update" do
      { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false }.each do |role, allowed|
        it "#{allowed ? 'permits' : 'refuses'} a #{role}" do
          actor = role == "OWNER" ? team.owner : member(role)

          expect(ProjectPolicy.new(actor, project).update?).to be(allowed)
        end
      end
    end

    # The Story: *"arquivar exige ADMIN"*. Archiving takes a Project out of
    # everybody's list, so it sits with the management row, not the contributor
    # one — a DEVELOPER may create a Project and may not archive one.
    describe "archive" do
      { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => false, "VIEWER" => false }.each do |role, allowed|
        it "#{allowed ? 'permits' : 'refuses'} a #{role}" do
          actor = role == "OWNER" ? team.owner : member(role)

          expect(ProjectPolicy.new(actor, project).archive?).to be(allowed)
        end
      end
    end

    # AC9's other half: a VIEWER reads. A role that could not read would make the
    # membership useless, and a matrix where nobody is refused anything is a
    # matrix nobody is enforcing.
    describe "view" do
      ROLES.each do |role|
        it "permits a #{role}" do
          actor = role == "OWNER" ? team.owner : member(role)

          expect(ProjectPolicy.new(actor, project).view?).to be(true)
        end
      end
    end
  end

  describe "deny by default" do
    it "refuses an actor with no membership at all" do
      expect(ProjectPolicy.new(create(:user), project).view?).to be(false)
    end

    it "refuses an actor whose membership was suspended, on the very next call" do
      actor = member("ADMIN")
      expect(ProjectPolicy.new(actor, project).archive?).to be(true)

      team.team_members.find_by(user_id: actor.id).update_columns(status: "SUSPENDED")

      expect(ProjectPolicy.new(actor, project).archive?).to be(false)
    end

    it "refuses a nil actor" do
      expect(ProjectPolicy.new(nil, project).view?).to be(false)
    end

    # AC2 of M01-04, applied to this Policy: an action nobody registered is
    # denied, and the omission is detectable as a programming error rather than
    # being an implicit permission.
    it "raises for an action nobody registered" do
      expect { ProjectPolicy.permitted_roles(:deploy) }
        .to raise_error(ApplicationPolicy::UnregisteredAction, /deploy/)
    end

    it "denies an unregistered action rather than allowing it" do
      decision = ProjectPolicy.new(team.owner, project).decide(:deploy)

      expect(decision).to be_denied
      expect(decision.reason).to eq(:unregistered_action)
    end
  end

  # Reuse asserted, not assumed. If somebody copies the matrix into this Policy,
  # the copy will be correct on the day it is written and wrong afterwards.
  describe "the rules are references to doc 04 §6.2, not copies" do
    it "reads view and update from the same table TeamPolicy declares" do
      expect(ProjectPolicy::PERMISSIONS[:view]).to equal(TeamPolicy::PERMISSIONS[:view])
      expect(ProjectPolicy::PERMISSIONS[:update]).to equal(TeamPolicy::PERMISSIONS[:create_project])
    end
  end

  # AC4 — nobody outside the Team lists, reads or mutates. Asserted through the
  # Commands rather than through the Policy alone: a Policy that says no while a
  # Command mutates anyway is the defect this criterion exists to catch.
  describe "cross-team (AC4)" do
    let(:outsider) { create(:team).owner }

    it "refuses to read" do
      expect(ProjectPolicy.new(outsider, project).view?).to be(false)
    end

    it "refuses to create in a Team the actor does not belong to" do
      expect { CreateProject.call(actor: outsider, team: team, name: "Theirs") }
        .to raise_error(Opanel::Authorization::Denied)

      expect(team.projects.where(name: "Theirs")).to be_empty
    end

    it "refuses to update" do
      expect { UpdateProject.call(actor: outsider, project: project, name: "Renamed") }
        .to raise_error(Opanel::Authorization::Denied)

      expect(project.reload.name).not_to eq("Renamed")
    end

    it "refuses to archive" do
      expect { ArchiveProject.call(actor: outsider, project: project) }
        .to raise_error(Opanel::Authorization::Denied)

      expect(project.reload.status).to eq("ACTIVE")
    end

    # The tenancy boundary is the other half, and it is the one that decides
    # whether the resource can even be reached (Annex C §7.3). A denial the
    # outsider can distinguish from absence is an existence oracle.
    it "cannot reach the Project through the tenancy boundary either" do
      expect(TenantScope.for(outsider, Project).find(project.id)).to be_nil
    end

    it "records the denial in the audit trail, with the classified reason" do
      expect {
        begin
          ArchiveProject.call(actor: outsider, project: project)
        rescue Opanel::Authorization::Denied
          nil
        end
      }.to change { AuditLog.where(action: "authorization.denied").count }.by(1)

      record = AuditLog.where(action: "authorization.denied").last
      expect(record.result).to eq("DENIED")
      expect(record.after).to eq({ "reason" => "no_membership" })
    end
  end

  # A DEVELOPER is inside the Team and still may not archive. Without this, the
  # cross-team examples above would be the only denials in the file and the
  # matrix would be indistinguishable from "members may do anything".
  describe "inside the Team, the role still decides" do
    it "refuses a DEVELOPER the archive their own Team's Project" do
      developer = member("DEVELOPER")

      expect { ArchiveProject.call(actor: developer, project: project) }
        .to raise_error(Opanel::Authorization::Denied)

      expect(project.reload.status).to eq("ACTIVE")
    end

    it "refuses a VIEWER the rename of their own Team's Project" do
      viewer = member("VIEWER")

      expect { UpdateProject.call(actor: viewer, project: project, name: "Renamed") }
        .to raise_error(Opanel::Authorization::Denied)
    end
  end
end
