require "rails_helper"

# AC2, the way the Story asks for it: two connections, a barrier, and a real
# COMMIT (Annex D §5.1).
#
# The race is the one that actually exists in the product. A Team whose OWNER was
# suspended is in OWNERSHIP_RECOVERY_REQUIRED, and an application looking for an
# *active* OWNER sees no one holding the seat; two administrators recovering it
# at the same moment is the scenario doc 04 §4.3 requires a lock or a constraint
# for. The Story's own Failure Scenarios name it: "duas transações tentam criar o
# segundo OWNER ativo".
#
# The point is not that two writes collide — it is *where*. Both threads run the
# check an application would run, and both find no active OWNER, because the
# barrier guarantees neither has written when either reads. An application-level
# guard approves both. The database refuses both, which is the claim
# "no banco, não apenas na aplicação": the seat is held by the OWNER while they
# are suspended, not only while they are active, so recovery is not a window in
# which the Team can be taken.
#
# `:concurrent` turns off transactional tests for these examples (see
# `spec/support/concurrency.rb`), so every write here really commits — and this
# file cleans up after itself.
RSpec.describe "two transactions racing for ownership of one Team", :concurrent, type: :integration do
  let(:namespace) { unique_namespace("team") }
  let(:slug) { namespace.downcase.gsub(/[^a-z0-9-]/, "-") }
  let(:digest) { Opanel::PasswordHashing.create("hunter2-hunter2-hunter2") }

  def user_named(name)
    User.create!(email: "#{slug}-#{name}@example.test", display_name: name, password_digest: digest)
  end

  let(:owner) { user_named("owner") }
  let(:first_challenger) { user_named("a") }
  let(:second_challenger) { user_named("b") }

  # An ACTIVE Team with its OWNER, committed.
  let(:team) do
    created = nil

    ActiveRecord::Base.transaction do
      created = Team.create!(name: "Race #{slug}", slug: slug, owner_user_id: owner.id)
      TeamMember.create!(team: created, user: owner, role: "OWNER", status: "ACTIVE",
        joined_at: Time.current)
    end

    created
  end

  # The Team after a security suspension of its OWNER, with two ADMINs on it.
  # Reached through the Command, so the fixture is a state the product actually
  # produces: both rows move in one transaction because the database accepts
  # neither alone.
  def team_in_recovery
    SuspendTeamMember.call(actor: SuspendTeamMember::SECURITY_PROCEDURE, team: team,
      user_id: Opanel::Identifier.external(:user, owner.id))

    [ first_challenger, second_challenger ].each do |user|
      TeamMember.create!(team: team, user: user, role: "ADMIN", status: "ACTIVE", joined_at: Time.current)
    end

    team
  end

  after do
    ActiveRecord::Base.transaction do
      TeamMember.where(team_id: Team.where("slug LIKE ?", "#{slug}%").select(:id)).delete_all
      Team.where("slug LIKE ?", "#{slug}%").delete_all
    end

    User.where("email LIKE ?", "#{slug}-%").delete_all
  end

  # A Team waiting for recovery is the moment worth racing for: its OWNER is
  # SUSPENDED, so an application-level guard looking for an *active* OWNER finds
  # none and lets both threads through. The database has to be what refuses, and
  # it has to refuse **both** — the suspended OWNER still holds the seat, which is
  # what stops a Team from being taken during exactly the window in which it
  # awaits the administrative recovery of M11-04.
  #
  # An earlier version of this example expected one of the two to commit. That
  # expectation was the bug: it left the Team with a live OWNER who was not
  # `teams.owner_user_id`, and wrote that incoherent state down as the correct
  # outcome of a legitimate race.
  it "refuses both simultaneous OWNER claims on a Team awaiting recovery" do
    recovering = team_in_recovery
    original_owner_id = recovering.owner_user_id
    both_have_checked = barrier(2)

    claim = lambda do |user|
      lambda do
        # The guard an application would write. It passes in both threads.
        slot_taken = TeamMember.exists?(team_id: recovering.id, role: "OWNER", status: "ACTIVE")
        both_have_checked.wait

        begin
          TeamMember.where(team_id: recovering.id, user_id: user.id).update_all(role: "OWNER")
          [ :committed, slot_taken ]
        rescue ActiveRecord::RecordNotUnique => error
          [ error, slot_taken ]
        end
      end
    end

    outcomes = concurrently(claim.call(first_challenger), claim.call(second_challenger))

    expect(outcomes.map(&:last)).to eq([ false, false ]),
      "the barrier did not force the interleaving: both threads must read before either writes"

    results = outcomes.map(&:first)
    expect(results.count(:committed)).to eq(0)

    expect(results).to all(be_a(ActiveRecord::RecordNotUnique))
    expect(results.map(&:message)).to all(include("index_team_members_one_active_owner_per_team"))

    # The seat never changed hands, and the Team still points at the owner it had.
    expect(TeamMember.where(team_id: recovering.id, role: "OWNER", status: "ACTIVE").count).to eq(0)
    expect(TeamMember.where(team_id: recovering.id, role: "OWNER").pluck(:user_id))
      .to eq([ original_owner_id ])
    expect(recovering.reload.owner_user_id).to eq(original_owner_id)
  end

  # There is deliberately no companion example racing two *first* owners. It
  # cannot be staged: `fk_teams_active_owner_membership` means a Team never
  # exists persisted without its OWNER, so outside a transaction the setup itself
  # is refused. The only race the schema permits is the one above.

  it "refuses at COMMIT a Team that never got its OWNER (AC3)" do
    # Not `SET CONSTRAINTS ALL IMMEDIATE` this time: this example commits for
    # real, so the deferred key is checked at the point production checks it.
    expect {
      ActiveRecord::Base.transaction do
        Team.create!(name: "Orphan #{slug}", slug: "#{slug}-orphan", owner_user_id: owner.id)
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /fk_teams_active_owner_membership/)

    expect(Team.where(slug: "#{slug}-orphan")).not_to exist
  end

  it "commits the Team and its OWNER together (AC1)" do
    expect { team }.not_to raise_error
    expect(TeamMember.where(team_id: team.id, role: "OWNER", status: "ACTIVE").count).to eq(1)
  end
end
