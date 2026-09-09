require "rails_helper"

# The concurrent half of AC5, which the first version of this Story asserted only
# in a comment.
#
# Two administrators revoking each other at the same moment is the case the lock
# exists for. The invariant that must survive is "never zero active
# administrators", and the *manner* matters too: the Story's Failure Scenarios ask
# for "rejeitada com erro estável", so the caller that loses has to receive a
# `Result.failure` it can render — not a driver exception.
#
# The first implementation locked the grant being revoked and *then* the surviving
# admins, which inverts the acquisition order between the two callers and
# deadlocks: it reproduced 6 times out of 6, one side raising
# `ActiveRecord::Deadlocked`. Locking the admin set first, in `id` order, is what
# makes both callers queue for the same rows in the same sequence.
RSpec.describe "two administrators revoking each other at once", :concurrent, type: :integration do
  let(:namespace) { unique_namespace("revoke") }
  let(:slug) { namespace.downcase.gsub(/[^a-z0-9-]/, "-") }
  let(:digest) { Opanel::PasswordHashing.create("hunter2-hunter2-hunter2") }

  def user_named(name)
    User.create!(email: "#{slug}-#{name}@example.test", display_name: name, password_digest: digest)
  end

  after do
    ActiveRecord::Base.transaction do
      users = User.where("email LIKE ?", "#{slug}-%").select(:id)
      InstanceRole.where(user_id: users).delete_all
      User.where(id: users).delete_all
    end
  end

  it "refuses one and revokes the other, without raising" do
    first = user_named("a")
    second = user_named("b")
    first_grant = InstanceRole.create!(user: first, role: InstanceRole::ADMIN)
    second_grant = InstanceRole.create!(user: second, role: InstanceRole::ADMIN)

    both_have_read = barrier(2)

    revoke = lambda do |actor, target|
      lambda do
        # Both callers see two administrators before either writes: an
        # application-level "there are two of us, so this is safe" approves both.
        seen = InstanceRole.active.admins.count
        both_have_read.wait

        begin
          [ RevokeInstanceRole.call(actor: actor, instance_role: target), seen ]
        rescue ActiveRecord::Deadlocked => error
          # Narrow on purpose. This is the one exception the example exists to
          # detect, and catching it here is what lets the assertion below name it
          # instead of the run dying with a stack trace. Anything else propagates:
          # a broad rescue in a spec hides the defect it was written to find.
          [ error, seen ]
        end
      end
    end

    outcomes = concurrently(
      revoke.call(first, second_grant),
      revoke.call(second, first_grant)
    )

    expect(outcomes.map(&:last)).to eq([ 2, 2 ]),
      "the barrier did not force the interleaving: both callers must read before either writes"

    results = outcomes.map(&:first)

    # No deadlock — this is the half that was failing.
    expect(results.grep(ActiveRecord::Deadlocked)).to be_empty,
      "a revocation deadlocked instead of refusing: #{results.grep(Exception).map(&:class).inspect}"

    expect(results.count(&:success?)).to eq(1)

    refused = results.find(&:failure?)
    expect(refused.code).to eq("INVALID_STATE_TRANSITION")
    expect(refused.message).to match(/without an administrator/i)

    # And the installation still has somebody who can administer it.
    expect(InstanceRole.active.admins.where(user_id: [ first.id, second.id ]).count).to eq(1)
  end
end
