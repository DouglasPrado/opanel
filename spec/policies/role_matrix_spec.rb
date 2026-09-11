require "rails_helper"

# AC6: the matrix of doc 04 §6.2, covered by test.
#
# The table is transcribed here **independently** of `TeamPolicy::PERMISSIONS`
# rather than read from it. A spec that iterates the constant it is checking
# proves only that the constant equals itself; transcribing the document means a
# change to the code has to be matched by a deliberate change here, and a typo in
# either shows up as a disagreement.
RSpec.describe "the role matrix of doc 04 §6.2", type: :policy do
  # rows: action => { role => allowed }. `nil` roles are absent from the table.
  MATRIX = {
    transfer_ownership: { "OWNER" => true, "ADMIN" => false, "DEVELOPER" => false, "VIEWER" => false },
    delete_team: { "OWNER" => true, "ADMIN" => false, "DEVELOPER" => false, "VIEWER" => false },
    rotate_recovery_key: { "OWNER" => true, "ADMIN" => false, "DEVELOPER" => false, "VIEWER" => false },
    manage_members: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => false, "VIEWER" => false },
    manage_clusters: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => false, "VIEWER" => false },
    drain_node: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => false, "VIEWER" => false },
    reveal_production_secret: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => false, "VIEWER" => false },
    create_project: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    create_environment: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    deploy: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    rollback: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    restart_service: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    scale_service: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    edit_secret: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => false },
    # Not a row of doc 04 §6.2. It is an addition, recorded here as one rather
    # than smuggled in: "may this actor see this Team at all" is the read that
    # `Team.accessible_to` already performs, and giving it a name means the
    # decision is reviewable instead of implicit. It grants nothing beyond what an
    # active membership already gave.
    view: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => true },
    view_logs: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => true },
    view_metrics: { "OWNER" => true, "ADMIN" => true, "DEVELOPER" => true, "VIEWER" => true }
  }.freeze

  let(:owner) { create(:user) }
  let(:team) { create(:team, owner: owner) }

  def actor_with(role)
    return owner if role == "OWNER"

    user = create(:user)
    create(:team_member, team: team, user: user, role: role, status: "ACTIVE")
    user
  end

  MATRIX.each do |action, by_role|
    describe "#{action}" do
      by_role.each do |role, allowed|
        it "#{allowed ? 'allows' : 'denies'} #{role}" do
          decision = Opanel::Authorization.authorize(actor_with(role), action, team)

          expect(decision.allowed?).to be(allowed)
          expect(decision.reason).to eq(:insufficient_role) unless allowed
        end
      end
    end
  end

  # The two directions of "the matrix is complete": nothing the document lists is
  # missing from the code, and nothing the code invents is missing from the
  # document. Without the second, an action could be added to `PERMISSIONS` and
  # never appear in any review of the matrix.
  describe "the matrix and the Policy agree on which actions exist" do
    it "declares every action the document lists" do
      expect(TeamPolicy.registered_actions).to include(*MATRIX.keys)
    end

    it "declares no action neither the document nor this file lists" do
      expect(TeamPolicy.registered_actions - MATRIX.keys).to be_empty
    end

    # `view` is the one action here that doc 04 §6.2 does not contain. Naming it
    # explicitly keeps the "transcribed from the document" claim honest: everything
    # else in MATRIX is a row of that table.
    it "names its one departure from the document" do
      documented = MATRIX.keys - [ :view ]

      expect(documented.length).to eq(16)
      expect(documented).not_to include(:view)
    end
  end
end
