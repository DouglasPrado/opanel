require "rails_helper"

# AC3, AC7, AC8, AC9, AC10 and AC11, against real PostgreSQL.
RSpec.describe "the audit trail", type: :integration do
  let(:password) { "hunter2-hunter2-hunter2" }

  def register(email)
    RegisterUser.call(email: email, display_name: "Somebody", password: password,
      ip: "203.0.113.7", user_agent: "rspec")
  end

  describe "the identity actions of this Milestone (AC3)" do
    it "records the bootstrap, with the Team it created" do
      result = register("first@example.test")
      team = result.value[:team]

      entry = AuditLog.find_by(action: AuditLog::ACTIONS[:installation_bootstrapped])

      expect(entry).to be_present
      expect(entry.team_id).to eq(team.id)
      expect(entry.actor_id).to eq(result.value[:user].id)
      expect(entry.result).to eq("SUCCESS")
    end

    it "records a registration" do
      user = register("someone@example.test").value[:user]

      entry = AuditLog.find_by(action: AuditLog::ACTIONS[:user_registered])

      expect(entry.actor_id).to eq(user.id)
      expect(entry.resource_type).to eq("User")
      expect(entry.ip.to_s).to eq("203.0.113.7")
    end

    it "records a sign-in" do
      register("returning@example.test")

      AuthenticateUser.call(email: "returning@example.test", password: password,
        ip: "198.51.100.4", user_agent: "rspec")

      entry = AuditLog.where(action: AuditLog::ACTIONS[:user_signed_in]).last

      expect(entry).to be_present
      expect(entry.resource_type).to eq("Session")
    end

    it "records a Team creation" do
      register("owner@example.test")
      actor = register("builder@example.test").value[:user]

      team = CreateTeam.call(actor: actor, name: "Second").value[:team]

      entry = AuditLog.find_by(action: AuditLog::ACTIONS[:team_created], resource_id: team.id)

      expect(entry.team_id).to eq(team.id)
      expect(entry.after["name"]).to eq("Second")
    end

    it "records a session revocation" do
      registration = register("revoker@example.test")
      user = registration.value[:user]
      session = registration.value[:session]

      RevokeSession.call(actor: user, session_id: session.external_id)

      entry = AuditLog.find_by(action: AuditLog::ACTIONS[:session_revoked])

      expect(entry).to be_present
      expect(entry.actor_id).to eq(user.id)
    end
  end

  describe "correlation (AC7)" do
    it "always carries a request id and a correlation id" do
      register("correlated@example.test")

      expect(AuditLog.count).to be > 0
      expect(AuditLog.where(request_id: [ nil, "" ])).to be_empty
      expect(AuditLog.where(correlation_id: [ nil, "" ])).to be_empty
    end

    # The database refuses a blank one too, so a caller that forgets cannot write
    # an uncorrelatable record.
    it "is refused by the database when blank" do
      expect {
        AuditLog.new(
          team_id: nil, actor_type: "SYSTEM", action: AuditLog::ACTIONS[:user_registered],
          resource_type: "User", request_id: " ", correlation_id: "c", result: "SUCCESS",
          created_at: Time.current
        ).save!(validate: false)
      }.to raise_error(ActiveRecord::StatementInvalid, /request_id_present/)
    end
  end

  describe "the chain from one request (AC8)" do
    it "returns everything that happened under it, in order" do
      Current.request_id = "req_chain_example"
      register("chained@example.test")

      chain = AuditTrailForResource.for_request("req_chain_example")

      expect(chain.map(&:action)).to include(
        AuditLog::ACTIONS[:user_registered],
        AuditLog::ACTIONS[:installation_bootstrapped]
      )
      expect(chain.map(&:created_at)).to eq(chain.map(&:created_at).sort)
    ensure
      Current.request_id = nil
    end
  end

  describe "the indexes the trail reads through (AC9)" do
    it "declares both of doc 09 §18, plus the request chain" do
      names = ActiveRecord::Base.connection.indexes("audit_logs").map(&:name)

      expect(names).to include(
        "index_audit_logs_on_team_id_and_created_at",
        "index_audit_logs_on_resource_and_created_at",
        "index_audit_logs_on_request_id"
      )
    end

    # PostgreSQL picks a sequential scan on a table this small whatever indexes
    # exist, so asserting the *default* plan would assert the size of the test
    # fixture rather than the shape of the query. Disabling seqscan for the
    # statement asks the question that matters — **can** this query be served by
    # the index, or does its shape prevent it (wrong column order, a leading
    # wildcard, a function on the column)? That is what a floor of 1,000,000 rows
    # in Annex B §9.1 will depend on.
    def plan_with_index_preferred(relation)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
        relation.explain.inspect
      end
    end

    it "can serve a resource trail from the resource index" do
      register("indexed@example.test")
      team = Team.first

      plan = plan_with_index_preferred(AuditLog.for_resource("Team", team.id))

      expect(plan).to include("index_audit_logs_on_resource_and_created_at")
    end

    it "can serve a request chain from the request index" do
      plan = plan_with_index_preferred(AuditLog.for_request("req_x"))

      expect(plan).to include("index_audit_logs_on_request_id")
    end

    it "can serve a Team trail from the team index" do
      register("teamindexed@example.test")
      team = Team.first

      relation = AuditLog.where(team_id: team.id).order(created_at: :desc)

      expect(plan_with_index_preferred(relation))
        .to include("index_audit_logs_on_team_id_and_created_at")
    end
  end

  describe "tenancy of the record (AC10)" do
    it "refuses a tenant-scoped action with no Team" do
      entry = AuditLog.new(
        team_id: nil, actor_type: "USER", action: AuditLog::ACTIONS[:team_created],
        resource_type: "Team", request_id: "r", correlation_id: "c", result: "SUCCESS"
      )

      expect(entry.valid?).to be(false)
      expect(entry.errors[:team_id].join).to match(/not an installation event/)
    end

    it "allows an installation event with no Team" do
      entry = AuditLog.new(
        team_id: nil, actor_type: "SYSTEM",
        action: AuditLog::ACTIONS[:user_registered], resource_type: "User",
        request_id: "r", correlation_id: "c", result: "SUCCESS"
      )

      expect(entry.valid?).to be(true)
    end

    it "leaves no tenant-scoped record without a Team after real activity" do
      register("tenant@example.test")
      actor = register("second@example.test").value[:user]
      CreateTeam.call(actor: actor, name: "Theirs")

      orphaned = AuditLog.where(team_id: nil)
        .where.not(action: AuditLog::INSTANCE_ACTIONS)

      expect(orphaned).to be_empty
    end
  end

  describe "audit sharing the mutation's transaction (AC11)" do
    it "rolls the mutation back when the trail cannot be written" do
      register("owner@example.test")
      owner = User.find_by(email: "owner@example.test")
      team = Team.first
      target = create(:team_member, team: team, user: create(:user))

      allow(AuditTrail).to receive(:record).and_raise(ActiveRecord::StatementInvalid, "audit down")

      expect {
        SuspendTeamMember.call(actor: owner, team: team, user_id: target.user.external_id)
      }.to raise_error(ActiveRecord::StatementInvalid)

      # The suspension did not happen: a member losing access with no record of
      # who removed it is what the criterion exists to prevent.
      expect(target.reload.status).to eq("ACTIVE")
    end
  end
end
