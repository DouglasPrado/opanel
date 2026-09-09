require "rails_helper"

# AC2, the way the Story asks: two simultaneous first registrations produce **one**
# bootstrap. Two connections, a barrier, and a real COMMIT (Annex D §5.1).
#
# The barrier is what makes this a test of the database rather than of luck. Both
# threads pass the point where an application would have asked "is the installation
# empty?" before either has written, so a guard written in Ruby approves both. Only
# `index_instance_roles_single_bootstrap` refuses one — which is the claim the
# Story's Security Requirements make: "duas requisições simultâneas de primeiro
# cadastro não podem gerar dois INSTANCE_ADMIN de bootstrap".
#
# `:concurrent` turns off transactional tests for this file (see
# `spec/support/concurrency.rb`), so every write really commits — and it cleans up
# after itself.
RSpec.describe "two simultaneous first registrations", :concurrent, type: :integration do
  let(:namespace) { unique_namespace("boot") }
  let(:slug) { namespace.downcase.gsub(/[^a-z0-9-]/, "-") }
  let(:password) { "hunter2-hunter2-hunter2" }

  # This file does not run in a transaction, so the registration throttle counter
  # survives between runs. Each example gets its own address space and clears the
  # rows it created, or the third run of the file starts failing on a rate limit
  # that has nothing to do with what is being tested.
  let(:first_ip) { "203.0.113.#{rand(1..254)}" }
  let(:second_ip) { "198.51.100.#{rand(1..254)}" }

  after do
    ActiveRecord::Base.transaction do
      AuthenticationAttempt.delete_all
      users = User.where("email LIKE ?", "#{slug}-%").select(:id)
      # M01-05 made these flows write an audit trail, and this file does not run
      # in a transaction: without this the records survive into the next spec file
      # and fail it for a reason that has nothing to do with the code under test.
      AuditLog.where(actor_id: users).delete_all
      InstanceRole.where(user_id: users).delete_all
      teams = Team.where(owner_user_id: users).select(:id)
      TeamMember.where(team_id: teams).delete_all
      TeamMember.where(user_id: users).delete_all
      Team.where(id: teams).delete_all
      Session.where(user_id: users).delete_all
      User.where(id: users).delete_all
    end
  end

  it "produces exactly one bootstrap, and the loser is an ordinary sign-up" do
    both_have_checked = barrier(2)

    register = lambda do |name, ip|
      lambda do
        # The guard an application would write, before anybody has written.
        looked_empty = !InstanceRole.bootstrapped?
        both_have_checked.wait

        result = RegisterUser.call(email: "#{slug}-#{name}@example.test",
          display_name: name, password: password, ip: ip, user_agent: "rspec")

        raise "registration failed: #{result.code} #{result.message}" unless result.success?

        [ result.value[:bootstrapped], looked_empty ]
      end
    end

    outcomes = concurrently(register.call("a", first_ip), register.call("b", second_ip))

    expect(outcomes.map(&:last)).to eq([ true, true ]),
      "the barrier did not force the interleaving: both threads must check before either writes"

    bootstrapped = outcomes.map(&:first)
    expect(bootstrapped.count(true)).to eq(1)
    expect(bootstrapped.count(false)).to eq(1)

    # And the durable state agrees with what the two calls reported.
    expect(InstanceRole.bootstrap.count).to eq(1)
    expect(InstanceRole.active.admins.count).to eq(1)
    expect(User.where("email LIKE ?", "#{slug}-%").count).to eq(2)
    # The loser is a real account — it simply administers nothing.
    loser_ids = User.where("email LIKE ?", "#{slug}-%")
      .where.not(id: InstanceRole.bootstrap.select(:user_id)).pluck(:id)
    expect(loser_ids.length).to eq(1)
    expect(InstanceRole.where(user_id: loser_ids)).not_to exist
    expect(Team.where(owner_user_id: loser_ids)).not_to exist
  end
end
