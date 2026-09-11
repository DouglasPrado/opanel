require "rails_helper"

# AC8 and AC10 — the two security criteria of this Story, asserted against the
# repository and against the running process rather than against a comment.
#
# doc 06 §4.2: the socket stays local to authorized administrative components, the
# daemon is never published on `0.0.0.0:2375`, and the browser never speaks to
# Docker. doc 04 §14.2 and AC10: the Swarm join token is a credential that lets
# anybody join the cluster, and it must not survive in a log, an audit record or
# a response.
RSpec.describe "the Docker API is not exposed", type: :security do
  # Where a Docker client may legitimately live (AF-02's `docker_boundaries`).
  # Anything outside these that starts a `docker` process is a second privileged
  # boundary, which is a Tier-0 change requiring an ADR.
  ALLOWED_DOCKER_PATHS = %w[
    app/executors/
    spec/support/swarm_lab
    bin/swarm-lab
    lib/gates/swarm_lab.rb
  ].freeze

  # The files that talk *about* Docker without talking *to* it: this spec, the
  # fitness functions and the configuration that lists the boundary.
  SELF_REFERENTIAL = %w[
    spec/security/docker_api_exposure_spec.rb
    lib/gates/fitness_functions.rb
    lib/gates/workspace_guardrail.rb
    config/architecture/fitness.yml
    config/architecture/docker-lab.yml
    spec/integration/swarm_bootstrap_lab_spec.rb
    spec/integration/swarm_lab_spec.rb
    spec/integration/cluster_bootstrap_spec.rb
  ].freeze

  def repository_files
    Dir.glob(Rails.root.join("{app,lib,config,bin,spec,db}/**/*"))
      .select { |path| File.file?(path) }
      .map { |path| path.delete_prefix("#{Rails.root}/") }
      .reject { |path| SELF_REFERENTIAL.include?(path) }
  end

  def read(path) = File.read(Rails.root.join(path), encoding: "BINARY")

  # Comments are not code, and neither is prose inside a diagnostic string.
  #
  # The first version of this file scanned raw text and reported five offenders,
  # every one of them a sentence *explaining* the rule: this spec's own comment
  # about port 2375, `states.tsx` naming `/var/run/docker.sock` as an example of
  # what it must never render, and `pack_spec` quoting "`docker pull busybox`
  # hangs" inside a fixture. AF-02 solved this before, and its comment says why:
  # "A rule that fires on a line explaining the rule trains people to ignore it."
  def code(path)
    read(path).each_line.reject { |line| line.strip.start_with?("#", "//", "*", "/*") }.join
  end

  describe "the unencrypted Docker port (AC8)" do
    # 2375 is the port doc 06 §4.2 names. It must not appear as a destination
    # anywhere: not in code, not in configuration, not in a compose file.
    # As an *endpoint*, not as a number: `tcp://…:2375`, a published port, or a
    # bind address. The bare digits appear in comments explaining the rule, and
    # firing on those is how a rule gets ignored.
    ENDPOINT_2375 = %r{tcp://[^\s"']*:2375|["']0\.0\.0\.0:2375|["']:2375|-p\s+\S*2375}

    it "appears nowhere in the repository as an endpoint" do
      offenders = repository_files.select { |path| code(path).match?(ENDPOINT_2375) }

      expect(offenders).to be_empty,
        "these files name port 2375 as an endpoint, which doc 06 §4.2 forbids:\n  #{offenders.join("\n  ")}"
    end

    # The control: the pattern has to recognise the thing it forbids, or it is a
    # check that cannot fail.
    it "would recognise a published Docker API" do
      expect('DOCKER_HOST="tcp://0.0.0.0:2375"').to match(ENDPOINT_2375)
      expect("-p 2375:2375").to match(ENDPOINT_2375)
      expect("# port 2375 is forbidden").not_to match(ENDPOINT_2375)
    end

    it "is not open on this machine" do
      # `false` means something is listening. `nil` means the check could not
      # decide, which is not a pass but is also not evidence of exposure.
      expect(SystemProbe.new.port_free?(2375)).not_to be(false)
    end

    # The control. Without it the assertion above passes on a machine where the
    # probe simply cannot bind anything, which would make it a check that cannot
    # fail.
    it "would notice a port that is held" do
      # Bound on every interface, because that is what the probe tries to bind.
      # Holding only loopback does not conflict with a `0.0.0.0` bind, and the
      # first version of this example proved that by passing.
      server = TCPServer.new("0.0.0.0", 0)
      taken = server.addr[1]

      expect(SystemProbe.new.port_free?(taken)).to be(false)
    ensure
      server&.close
    end

    it "never sets DOCKER_HOST to a network address" do
      offenders = repository_files.select { |path| code(path).match?(/DOCKER_HOST\s*=\s*["']?tcp:/) }

      expect(offenders).to be_empty
    end
  end

  # The half the first version of this file missed entirely.
  #
  # Not setting `DOCKER_HOST` is not the same as not having one: `Open3.capture3`
  # inherits the process environment, so an ambient value redirects every command
  # the executor runs — `swarm init` included — at a remote Engine. The class
  # comment claimed the local socket was the only destination "by construction",
  # and the independent review disproved it by exporting a TCP address and
  # watching a real call dial out. The only test here was a source grep, which
  # cannot see an environment variable.
  describe "the destination is checked, not assumed (AC8)" do
    around do |example|
      original = ENV.to_hash.slice("DOCKER_HOST", "DOCKER_CONTEXT")
      example.run
    ensure
      ENV.delete("DOCKER_HOST")
      ENV.delete("DOCKER_CONTEXT")
      original.each { |key, value| ENV[key] = value }
    end

    it "refuses a TCP endpoint before running anything" do
      ENV["DOCKER_HOST"] = "tcp://192.0.2.1:2376"

      expect { SwarmBootstrap.info }
        .to raise_error(SwarmBootstrap::EngineError) { |error|
          expect(error.cause_code).to eq(SwarmBootstrap::DAEMON_NOT_LOCAL)
        }
    end

    # `ssh://` is a legitimate Docker transport and still not a socket on this
    # machine. doc 06 §4.2 says remote access needs its own mechanism, so until
    # that exists there is no remote destination this may accept.
    it "refuses an SSH endpoint too" do
      ENV["DOCKER_HOST"] = "ssh://root@192.0.2.1"

      expect { SwarmBootstrap.info }
        .to raise_error(SwarmBootstrap::EngineError, /not a socket on this machine/)
    end

    it "refuses a value it cannot parse rather than guessing" do
      ENV["DOCKER_HOST"] = "192.0.2.1:2376"

      expect { SwarmBootstrap.info }
        .to raise_error(SwarmBootstrap::EngineError) { |error|
          expect(error.cause_code).to eq(SwarmBootstrap::DAEMON_ENDPOINT_UNKNOWN)
        }
    end

    # The refusal has to come *before* the command, or a redirected `swarm init`
    # has already built somebody else's cluster by the time anybody notices.
    it "refuses before the command runs" do
      ENV["DOCKER_HOST"] = "tcp://192.0.2.1:2376"

      expect(Open3).not_to receive(:capture3).with("docker", "swarm", anything, anything, anything)

      expect { SwarmBootstrap.init(advertise_address: "10.0.0.5") }
        .to raise_error(SwarmBootstrap::EngineError)
    end

    # The control: with the environment clean the same call reaches a local
    # socket, so the examples above fail on the redirection rather than on
    # everything being broken.
    it "accepts the local socket this machine actually uses" do
      ENV.delete("DOCKER_HOST")

      expect(SwarmBootstrap.endpoint).to match(%r{\A(unix|npipe)://})
    end
  end

  describe "the single privileged boundary (AC8)" do
    # The same rule AF-02 enforces, asserted from the suite as well: a second
    # place that starts a Docker process is a second place with the socket.
    it "starts a Docker process only from the declared boundary" do
      offenders = repository_files.select do |path|
        next false if ALLOWED_DOCKER_PATHS.any? { |allowed| path.start_with?(allowed) }

        code(path).match?(/(?:Open3\.(?:capture3|popen3|capture2)|system|spawn|exec)\(\s*["']docker["']/)
      end

      expect(offenders).to be_empty,
        "these files start a Docker process outside app/executors/:\n  #{offenders.join("\n  ")}"
    end

    # There is no `exec(command:)` in the executor, and there must never be: a
    # generic escape hatch makes the typed allowlist decorative.
    it "exposes no generic command primitive on the executor" do
      source = read("app/executors/swarm_bootstrap.rb")

      expect(source).not_to match(/def\s+self\.(exec|run_command|shell|system)\b/)
    end

    # The React tree must not learn about Docker at all. AF-04 covers server-only
    # imports; this covers the specific thing doc 06 §4.2 forbids — the browser
    # talking to the Engine.
    it "puts no Docker endpoint in the React tree" do
      offenders = Dir.glob(Rails.root.join("app/frontend/**/*.{ts,tsx}"))
        .map { |path| path.delete_prefix("#{Rails.root}/") }
        .select { |path| code(path).match?(%r{docker\.sock|tcp://\S*237[56]|DOCKER_HOST}) }

      expect(offenders).to be_empty
    end
  end

  describe "the Swarm join token (AC10)" do
    # Deliberately low-entropy, and deliberately still `SWMTKN-`-shaped.
    #
    # The first version used a value with a real token's entropy, and gitleaks
    # flagged it — correctly. What the redaction matches is the prefix
    # (`SwarmBootstrap::JOIN_TOKEN`), so the shape is the whole requirement; real
    # entropy added nothing to the test and taught the secret scanner to be
    # noisier about the one file whose job is to talk about credentials. The fix
    # is a fake that is obviously fake, never an allowlist entry.
    TOKEN = "SWMTKN-1-example-not-a-real-token-do-not-use-x1"

    it "is removed from anything the executor lets out" do
      raw = "To add a worker to this swarm, run: docker swarm join --token #{TOKEN} 10.0.0.5:2377"

      redacted = SwarmBootstrap.redact(raw)

      expect(redacted).not_to include(TOKEN)
      expect(redacted).not_to include("SWMTKN")
      expect(redacted).to include(SwarmBootstrap::REDACTED)
      # The rest of the sentence survives, or the operator is left with nothing.
      expect(redacted).to include("10.0.0.5:2377")
    end

    it "is removed wherever it appears, not only at the start" do
      expect(SwarmBootstrap.redact("prefix #{TOKEN} suffix #{TOKEN}")).not_to include("SWMTKN")
    end

    # The executor never returns the output of a mutating call, because that is
    # where the token is. Asserted on behaviour rather than on the shape of the
    # source: the command is made to answer with a real init message carrying a
    # token, and what comes back has to be the Swarm id the daemon reported
    # afterwards.
    it "returns the Swarm id read back from the daemon, never the init output" do
      leaking = "Swarm initialized: current node (abc) is now a manager.\n\n" \
                "To add a worker to this swarm, run: docker swarm join --token #{TOKEN} 10.0.0.5:2377"

      allow(SwarmBootstrap).to receive(:run!).and_return(leaking)
      allow(SwarmBootstrap).to receive(:info).and_return(
        SwarmBootstrap::Info.new(engine_version: "29.7.2", swarm_state: "active",
          swarm_id: "abcdefghij0123456789k", node_id: "n1", manager?: true, node_count: 1,
          data_root: "/var/lib/docker")
      )

      returned = SwarmBootstrap.init(advertise_address: "10.0.0.5")

      expect(returned).to eq("abcdefghij0123456789k")
      expect(returned).not_to include("SWMTKN")
    end

    it "refuses to initialise without an explicit advertise address" do
      expect { SwarmBootstrap.init(advertise_address: "  ") }
        .to raise_error(ArgumentError, /advertise address/)
    end

    # `AuditSanitizer` is an allowlist, so a token could only arrive under an
    # allowed key. Asserted rather than assumed: the Cluster's allowlist is the
    # one this Story added.
    it "has no column on Cluster that could hold it" do
      expect(Cluster.column_names).not_to include("join_token", "worker_token", "manager_token")
    end

    it "is not an allowed audit field for a Cluster" do
      allowed = AuditSanitizer::ALLOWED.fetch("Cluster")

      expect(allowed).not_to include("join_token", "token")
      # And a value planted under an allowed key is still scrubbed by the
      # redaction the Command applies before anything is written.
      expect(SwarmBootstrap.redact(TOKEN)).not_to include("SWMTKN")
    end
  end
end
