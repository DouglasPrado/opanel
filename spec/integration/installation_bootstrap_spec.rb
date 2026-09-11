require "rails_helper"

# AC1, AC3, AC4, AC7 and AC8, against real PostgreSQL. AC2 — the race — needs two
# connections and a real COMMIT, so it lives in
# `installation_bootstrap_concurrency_spec.rb`.
RSpec.describe "the first-installation bootstrap", type: :integration do
  let(:password) { "hunter2-hunter2-hunter2" }

  def register(email)
    RegisterUser.call(email: email, display_name: "First", password: password,
      ip: "203.0.113.1", user_agent: "rspec")
  end

  describe "the first registration on an empty installation (AC1)" do
    it "creates User, Team, OWNER membership and INSTANCE_ADMIN" do
      result = register("first@example.test")

      expect(result).to be_success
      expect(result.value[:bootstrapped]).to be(true)

      user = result.value[:user]
      team = result.value[:team]

      expect(team.owner_user_id).to eq(user.id)
      expect(team.team_members.find_by(user_id: user.id)).to have_attributes(
        role: "OWNER", status: "ACTIVE"
      )
      expect(InstanceRole.active.admins.where(user_id: user.id)).to exist
      expect(InstanceRole.find_by(user_id: user.id).granted_by_bootstrap).to be(true)
    end

    it "writes the four rows the criterion names, and one instance role" do
      # The bootstrap runs inside a SAVEPOINT so that a lost race can be discarded
      # without killing the registration.
      statements = []

      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statements << payload[:sql]
      end

      register("atomic@example.test")
      ActiveSupport::Notifications.unsubscribe(subscriber)

      inserts = statements.grep(/INSERT INTO/).join
      # The four the criterion names. Other writes on the path — the registration
      # throttle counter — are legitimate and not what AC1 is about, so the
      # assertion names tables rather than counting statements.
      expect(inserts).to include('INSERT INTO "users"')
      expect(inserts).to include('INSERT INTO "sessions"')
      expect(inserts).to include('INSERT INTO "teams"')
      expect(inserts).to include('INSERT INTO "team_members"')
      expect(statements.grep(/INSERT INTO "instance_roles"/).length).to eq(1)

      # There is deliberately no assertion about transaction depth or about the
      # absence of a `COMMIT` here. Both were tried and both are inert: the suite
      # already holds a transaction open for the example, so `open_transactions` is
      # never zero and no `COMMIT` is ever issued, whatever the command does — a
      # check that cannot fail is worse than no check, because it reads like proof.
      #
      # What this example proves is the composition: the four rows the criterion
      # names are written, and the instance role exactly once. **Atomicity is
      # proved by "an interrupted bootstrap leaves nothing behind" below**, which
      # was verified to go red when the bootstrap is moved outside the caller's
      # transaction.
    end

    it "emits `installation.bootstrapped` with the user, the team and the roles (AC7)" do
      logs = capture_logs { register("audited@example.test") }

      expect(logs).to include("installation.bootstrapped")
      expect(logs).to include("OWNER")
      expect(logs).to include("INSTANCE_ADMIN")
      expect(logs).not_to include(password)
    end
  end

  # doc 04 §3.1 and AC1 both say *empty installation*. "No bootstrap row yet" is a
  # different predicate, and the two diverge exactly where it is dangerous: an
  # installation that already has users but has never had this table. Both
  # directions are fixed here, because a rule asserted in only one of them is a
  # rule that can be inverted by accident.
  describe "an installation that already has users but no bootstrap grant" do
    before { create(:user, email: "existing@example.test") }

    it "does not hand the installation to the next person who registers" do
      result = register("newcomer@example.test")

      expect(result).to be_success
      expect(result.value[:bootstrapped]).to be(false)
      expect(InstanceRole.count).to eq(0)
      expect(Team.count).to eq(0)
    end

    it "leaves the newcomer an ordinary account, not an administrator" do
      user = register("newcomer@example.test").value[:user]

      expect(InstanceRole.where(user_id: user.id)).not_to exist
      expect(InstanceRole.active.admins.count).to eq(0)
    end
  end

  describe "an installation with no users at all" do
    it "does bootstrap — the guard refuses a populated installation, not every one" do
      expect(User.count).to eq(0)

      result = register("first@example.test")

      expect(result.value[:bootstrapped]).to be(true)
      expect(InstanceRole.active.admins.count).to eq(1)
    end
  end

  describe "an interrupted bootstrap (AC8)" do
    it "leaves nothing behind" do
      allow(InstanceRole).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { register("interrupted@example.test") }.to raise_error(ActiveRecord::StatementInvalid)

      expect(User.where(email: "interrupted@example.test")).not_to exist
      expect(Team.count).to eq(0)
      expect(TeamMember.count).to eq(0)
      expect(InstanceRole.count).to eq(0)
      expect(Session.count).to eq(0)
    end
  end

  describe "a registration after the bootstrap" do
    let!(:first) { register("owner@example.test") }

    it "is an ordinary sign-up with no instance role" do
      second = register("second@example.test")

      expect(second).to be_success
      expect(second.value[:bootstrapped]).to be(false)
      expect(InstanceRole.where(user_id: second.value[:user].id)).not_to exist
      expect(InstanceRole.bootstrap.count).to eq(1)
    end

    # AC3. The Story is explicit: creating a Team later grants TEAM_OWNER of that
    # Team and nothing else.
    it "grants only TEAM_OWNER when that user later creates a Team" do
      second = register("builder@example.test").value[:user]

      created = CreateTeam.call(actor: second, name: "Second Team")

      expect(created).to be_success
      expect(created.value[:membership]).to have_attributes(role: "OWNER", status: "ACTIVE")
      expect(InstanceRole.where(user_id: second.id)).not_to exist
    end

    # AC4. The transfer itself is M11-03; what is asserted here is the structural
    # reason it cannot carry the instance role — they are different tables, and
    # nothing in the Team path writes this one.
    it "keeps INSTANCE_ADMIN out of the Team's ownership entirely" do
      owner = first.value[:user]
      team = first.value[:team]
      successor = register("successor@example.test").value[:user]
      create(:team_member, :admin, team: team, user: successor)

      # The shape M11-03 will take: demote, promote, repoint. The instance role is
      # untouched by all three.
      ApplicationRecord.transaction do
        team.team_members.find_by(user_id: owner.id).update_columns(role: "ADMIN")
        team.team_members.find_by(user_id: successor.id).update_columns(role: "OWNER")
        team.update_columns(owner_user_id: successor.id)
      end

      expect(InstanceRole.active.admins.where(user_id: owner.id)).to exist
      expect(InstanceRole.where(user_id: successor.id)).not_to exist
    end
  end

  describe "InstallationBootstrapState" do
    it "reports an un-bootstrapped installation" do
      state = InstallationBootstrapState.call

      expect(state.value[:bootstrapped]).to be(false)
      expect(state.value[:administrator_count]).to eq(0)
    end

    it "reports who bootstrapped it and when" do
      user = register("state@example.test").value[:user]

      state = InstallationBootstrapState.call

      expect(state.value[:bootstrapped]).to be(true)
      expect(state.value[:administrator_count]).to eq(1)
      expect(state.value[:bootstrapped_by]).to eq(user.external_id)
      expect(state.value[:bootstrapped_at]).to be_present
    end
  end
end
