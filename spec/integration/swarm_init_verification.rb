require "rails_helper"

# AC1 of M01-08, against a real `docker swarm init`. **Not part of `bin/test`.**
#
# ## Why this is not a `_spec.rb`
#
# The example needs a daemon that is not in a Swarm. Every other real-Engine
# example in this repository needs one that is, and the only way to produce the
# first from the second is a destructive operation the workspace guardrail denies
# to the automated run — correctly. Under the suite's own policy a skipped
# example is not a passing one (`bin/gate post-commit` refuses any recorded skip),
# so an example that skips in the normal state cannot be counted, and pretending
# it ran would be the false claim the independent review caught in round 1.
#
# It is therefore an **operator-run verification**: the file name keeps it out of
# `rspec`'s default pattern, and it is executed by naming it, after the daemon
# has been taken down by a human:
#
#     bin/swarm-lab down
#     bundle exec rspec spec/integration/swarm_init_verification.rb --format documentation
#     # the example re-labels the lab itself; `bin/swarm-lab up` is idempotent
#
# Nothing about the assertions changed when it moved here. What changed is that
# the suite stops counting an example that cannot run inside it.
#
# Run history: docs/implementation/M01/evidence/M01-08-real-swarm-init.txt.
RSpec.describe "the real Swarm initialisation (M01-08 AC1)", swarm: false do
  let(:team) { create(:team) }

  let(:administrator) do
    InstanceRole.create!(user: team.owner, role: InstanceRole::ADMIN)
    team.owner
  end

  LAB_ADVERTISE_ADDRESS = "127.0.0.1" unless defined?(LAB_ADVERTISE_ADDRESS)

  def bootstrap(**arguments)
    BootstrapCluster.call(actor: administrator, team: team, name: "Lab",
      advertise_address: arguments.fetch(:advertise_address, LAB_ADVERTISE_ADDRESS))
  end

  describe "initialising an inactive daemon" do
    let(:label) { Opanel::Gates::SwarmLab.label(Rails.root.to_s) }

    before do
      skip "the Docker daemon is not reachable — run `bin/swarm-lab up`." unless SwarmBootstrap.reachable?

      if SwarmBootstrap.info.swarm_active?
        skip "this daemon is already in a Swarm, and taking it out is a destructive operation " \
             "this suite may not perform. Run `bin/swarm-lab down` first to cover this branch, " \
             "then `bin/swarm-lab up` to restore the lab."
      end
    end

    # One initialisation, and everything a real one has to be true about.
    #
    # Split in two, the second example could never run: the first takes the
    # daemon it needed. Each `bin/swarm-lab down` buys exactly one initialisation,
    # so both assertions are made about the same one — which is also honest, since
    # they *are* two facts about a single `docker swarm init`.
    it "turns an inactive daemon into a Swarm, registers its id, and leaks no join token" do
      expect(SwarmBootstrap.info).to be_swarm_inactive

      output = capture_log { @result = bootstrap(advertise_address: LAB_ADVERTISE_ADDRESS) }

      # Label first: an assertion failure after this point must not leave the lab
      # unidentifiable, which `assert_claimable!` would then refuse to reclaim.
      if @result.success?
        node = Opanel::Gates::SwarmLab.docker!("node", "inspect", "self", "--format", "{{.ID}}")
        Opanel::Gates::SwarmLab.docker!("node", "update", "--label-add", "#{label}=true", node)
      end

      expect(@result).to be_success

      cluster = @result.value.fetch(:cluster)
      expect(cluster.swarm_id).to match(Cluster::SWARM_ID_FORMAT)
      expect(cluster.swarm_id).to eq(SwarmBootstrap.info.swarm_id)
      expect(cluster.advertise_address).to eq(LAB_ADVERTISE_ADDRESS)
      expect(cluster.observed_at).to be_present
      expect(SwarmBootstrap.info).to be_swarm_active

      # AC10 against a real initialisation, which really does print a join token
      # in its success message.
      expect(output).not_to include("SWMTKN")
      expect(AuditLog.all.map { |record| record.attributes.to_s }.join).not_to include("SWMTKN")

      # The control: the daemon really does hold a token, so the absence above is
      # the redaction working rather than a Swarm that has none.
      expect(Opanel::Gates::SwarmLab.docker!("swarm", "join-token", "-q", "worker"))
        .to start_with("SWMTKN")
    end
  end

  private

  def capture_log
    original = Rails.logger
    buffer = StringIO.new
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(buffer))
    yield
    buffer.string
  ensure
    Rails.logger = original
  end
end
