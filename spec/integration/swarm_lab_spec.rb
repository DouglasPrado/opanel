require "rails_helper"
require "open3"

# The lab, exercised against a real Engine.
#
# Annex D §7 requires runtime behaviour to be tested against real infrastructure
# rather than a mock: a mock agrees with whatever the code believes, and the
# belief is the thing under test. From M01 the executor and the reconcilers run
# here; M00 proves the lab itself works and, more importantly, that it refuses to
# touch anything else.
RSpec.describe "Swarm lab", type: :integration do
  LAB = Opanel::Gates::SwarmLab
  ROOT = Rails.root.to_s

  describe "the guardrail" do
    # The property that matters most: the autonomous workspace must not be able to
    # reach a real cluster (Annex H §12.2), and a check that an environment
    # variable can disable is not a check.
    it "identifies the lab by a property of the daemon, not by configuration" do
      source = Rails.root.join("lib/gates/swarm_lab.rb").read

      expect(source).to match(/node.*inspect.*Spec\.Labels/m)
      expect(source).to match(/no environment variable that skips this check/)
    end

    it "refuses a daemon that does not carry the lab label" do
      allow(LAB).to receive(:available?).and_return(true)
      allow(LAB).to receive(:lab_daemon?).and_return(false)

      expect { LAB.assert_lab!(ROOT) }
        .to raise_error(LAB::NotTheLab, /may be a real cluster/)
    end

    it "names what to do rather than only refusing" do
      allow(LAB).to receive(:available?).and_return(true)
      allow(LAB).to receive(:lab_daemon?).and_return(false)

      LAB.assert_lab!(ROOT)
    rescue LAB::NotTheLab => error
      expect(error.message).to include("bin/swarm-lab up")
    end

    it "fails closed when Docker is unreachable, rather than assuming it is safe" do
      allow(LAB).to receive(:available?).and_return(false)

      expect { LAB.assert_lab!(ROOT) }.to raise_error(LAB::DockerUnavailable)
    end

    it "offers no environment variable that disables it" do
      source = Rails.root.join("lib/gates/swarm_lab.rb").read + Rails.root.join("bin/swarm-lab").read

      expect(source).not_to match(/ENV\[["'](SKIP|FORCE|ALLOW)_?\w*["']\]/),
        "a guardrail that can be exported away is not a guardrail"
    end

    # The hole the label could not cover: a daemon that has never been
    # initialised has no node to carry a label, so `up` ran `swarm init` against
    # whatever DOCKER_HOST pointed at. A real Engine waiting to join a cluster is
    # exactly that.
    describe "claiming a daemon that is not yet a lab" do
      before do
        allow(LAB).to receive(:available?).and_return(true)
        allow(LAB).to receive(:lab_daemon?).and_return(false)
      end

      it "refuses a daemon reached over the network" do
        allow(LAB).to receive(:endpoint).and_return("tcp://10.0.4.19:2376")

        expect { LAB.assert_claimable!(ROOT) }
          .to raise_error(LAB::NotTheLab, /Refusing to create a Swarm/)
      end

      it "refuses it before any mutation, not after" do
        allow(LAB).to receive(:endpoint).and_return("tcp://10.0.4.19:2376")
        # `docker!` is how every mutation leaves this process. If the guardrail
        # reaches it at all, the check ran too late to matter.
        expect(LAB).not_to receive(:docker!)

        expect { LAB.assert_claimable!(ROOT) }.to raise_error(LAB::NotTheLab)
      end

      it "accepts an inactive local daemon" do
        allow(LAB).to receive(:endpoint).and_return("")
        allow(LAB).to receive(:docker!)
          .with("info", "--format", "{{json .Swarm}}")
          .and_return('{"LocalNodeState":"inactive"}')

        expect(LAB.assert_claimable!(ROOT)).to be(true)
      end

      it "refuses a local daemon already running a swarm that is not ours" do
        allow(LAB).to receive(:endpoint).and_return("")
        allow(LAB).to receive(:docker!)
          .with("info", "--format", "{{json .Swarm}}")
          .and_return('{"LocalNodeState":"active"}')

        expect { LAB.assert_claimable!(ROOT) }
          .to raise_error(LAB::NotTheLab, /may be a real cluster/)
      end

      it "declares the claimable endpoints in a versioned file, not in an env var" do
        config = YAML.safe_load_file(Rails.root.join("config/architecture/docker-lab.yml"))

        expect(config.dig("lab", "claimable_endpoints")).to include("unix://")
        expect(config.dig("lab", "claimable_endpoints")).not_to include("tcp://0.0.0.0")
      end
    end
  end

  describe "the recorded Engine version" do
    it "is in a versioned file, so the compatibility suite knows what was exercised" do
      config = YAML.safe_load_file(Rails.root.join("config/architecture/docker-lab.yml"))

      expect(config.dig("engine", "minimum_version")).to be_present
      expect(config.dig("engine", "verified_against")).to be_present
      expect(config.dig("engine", "api_minimum")).to be_present
    end
  end

  describe "unique namespaces", :swarm do
    it "never repeats a resource name inside a run" do
      names = Array.new(4) { lab_name("svc") }

      expect(names.uniq.length).to eq(4)
    end

    it "ties a leaked resource to the run that made it" do
      expect(lab_name("svc")).to include(Process.pid.to_s)
      expect(lab_name("svc")).to start_with(lab_prefix)
    end
  end

  describe "a service lifecycle", :swarm do
    it "creates a service, observes its tasks, and removes it" do
      name = create_lab_service

      expect(lab_service_exists?(name)).to be(true)

      tasks = wait_for("the service to schedule a task") do
        found = lab_service_tasks(name)
        found unless found.empty?
      end

      expect(tasks).not_to be_empty
      expect(tasks.first).to include(name)

      cleanup_lab_resources

      expect(lab_service_exists?(name)).to be(false)
    end

    it "labels everything it creates, so status can find it" do
      name = create_lab_service

      expect(LAB.lab_services(ROOT)).to include(name)
      expect(LAB.orphaned_resources(ROOT)["services"]).to include(name)
    end
  end

  # M00-17 declares four resource kinds, and `status`/`reset` already looked for
  # orphaned secrets and configs — which nothing could create, so that half of
  # the cleanup path had never run.
  describe "a secret and a config lifecycle", :swarm do
    it "creates a secret, finds it, and removes it" do
      name = create_lab_secret

      expect(lab_resource_exists?("secret", name)).to be(true)
      expect(LAB.orphaned_resources(ROOT)["secrets"]).to include(name)

      cleanup_lab_resources

      expect(lab_resource_exists?("secret", name)).to be(false)
    end

    it "creates a config, finds it, and removes it" do
      name = create_lab_config

      expect(lab_resource_exists?("config", name)).to be(true)
      expect(LAB.orphaned_resources(ROOT)["configs"]).to include(name)

      cleanup_lab_resources

      expect(lab_resource_exists?("config", name)).to be(false)
    end
  end

  describe "cleanup" do
    # Needs the helpers but not the Engine: what is under test is what the
    # harness does with a failed removal, and `LAB.remove` is stubbed.
    include SwarmLabHelpers

    # The failure this replaces was silent: the exit code of `docker rm` was
    # discarded, so a resource that refused to go away became the next run's
    # inherited state and the run that leaked it still reported green.
    it "raises when a removal really fails, instead of discarding the exit code" do
      allow(LAB).to receive(:remove).with("service", "stuck").and_return("service stuck: in use")

      expect { cleanup_lab_resources([ [ "service", "stuck" ] ]) }
        .to raise_error(/could not be cleaned up/)
    end

    it "attempts every resource before it raises, so one failure strands nothing" do
      allow(LAB).to receive(:remove).with("service", "stuck").and_return("service stuck: in use")
      allow(LAB).to receive(:remove).with("network", "fine").and_return(nil)

      expect(LAB).to receive(:remove).with("network", "fine")

      expect { cleanup_lab_resources([ [ "service", "stuck" ], [ "network", "fine" ] ]) }
        .to raise_error(/could not be cleaned up/)
    end
  end

  describe "cleanup against the lab", :swarm do
    it "is idempotent after a simulated crash" do
      name = create_lab_service
      leaked = [ [ "service", name ] ]

      # The crash: the example's own list is emptied without removing anything,
      # exactly as an interrupted run would leave it.
      created_resources.clear

      expect(lab_service_exists?(name)).to be(true)

      cleanup_lab_resources(leaked.dup)
      expect(lab_service_exists?(name)).to be(false)

      # Running it again must not be an error — otherwise one failure poisons
      # every run after it.
      expect { cleanup_lab_resources([ [ "service", name ] ]) }.not_to raise_error
    end

    it "reports orphans so no test depends on inherited state" do
      name = create_lab_service

      expect(LAB.orphaned_resources(ROOT)["services"]).to include(name)
    end
  end

  describe "up and down", :swarm do
    def swarm_lab(*arguments)
      Open3.capture2e(Rails.root.join("bin/swarm-lab").to_s, *arguments, chdir: ROOT)
    end

    # The Story's acceptance criterion: twice in a row, both exiting 0.
    it "is idempotent across two full cycles" do
      2.times do |cycle|
        _out, status = swarm_lab("up")
        expect(status).to be_success, "up failed on cycle #{cycle + 1}"

        _out, status = swarm_lab("up")
        expect(status).to be_success, "the second `up` must be a no-op, not an error"

        _out, status = swarm_lab("down")
        expect(status).to be_success, "down failed on cycle #{cycle + 1}"

        out, status = swarm_lab("down")
        expect(status).to be_success, "the second `down` must be a no-op, not an error"
        expect(out).to match(/already down/)
      end

      # Leave the lab as this suite found it.
      swarm_lab("up")
    end
  end

  describe "when Docker is unavailable" do
    it "skips the suite explicitly rather than reporting it green" do
      support = Rails.root.join("spec/support/swarm_lab.rb").read

      expect(support).to match(/skip .*Docker daemon is not reachable/)
      expect(support).to match(/never reported as passing/)
    end

    it "makes `bin/swarm-lab up` fail with something actionable" do
      source = Rails.root.join("bin/swarm-lab").read

      expect(source).to match(/The Docker daemon is not reachable/)
      expect(source).to match(/Start Docker and try again/)
    end
  end
end
