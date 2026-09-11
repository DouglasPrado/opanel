require "rails_helper"
require "tmpdir"
require "yaml"
require_relative "../../lib/gates/fitness_functions"

# AC1, AC2, AC3, AC10 — the Tier-0 boundary (Annex C §8, T01), asserted against
# the repository and, for the fitness functions, against a controlled negative
# rather than against the absence of violations in a tree that has none.
RSpec.describe "the Swarm Executor is the only privileged boundary", type: :security do
  ROOT = Rails.root.to_s

  def read(path) = File.read(File.join(ROOT, path), encoding: "BINARY")

  # Comments are not code (the fitness functions' own rule).
  def code(path)
    read(path).each_line.reject { |line| line.strip.start_with?("#", "//", "*", "/*") }.join
  end

  def executor_sources = Dir.glob(File.join(ROOT, "app/executors/**/*.rb")).map { |p| p.delete_prefix("#{ROOT}/") }

  # AC3. There is no primitive that takes a command line, a shell string or a
  # free argument list to the daemon. The search is over code, not comments, and
  # the patterns are the ones that would appear if somebody added one.
  describe "no generic execution primitive (AC3)" do
    # What a generic primitive would look like. `Open3.capture3("docker", …)` is
    # deliberately **not** here: `SwarmBootstrap` starts the CLI with typed
    # arguments from inside the boundary, which is the allowed shape — the
    # forbidden one is a method that takes the command line from a caller.
    GENERIC = [
      /\bdef\s+(self\.)?(exec|run_command|shell|system|spawn|raw|command)\b/,
      /\bexec\s*\(/, /\bsystem\s*\(/, /\bspawn\s*\(/, /\bPTY\./, /`[^`\n]+`/,
      /\bpublic_send\s*\(/
    ].freeze

    it "exists nowhere in app/executors/" do
      offenders = executor_sources.flat_map do |path|
        GENERIC.filter_map { |pattern| "#{path}: #{pattern.source}" if code(path).match?(pattern) }
      end

      expect(offenders).to be_empty, offenders.join("\n")
    end

    # The control: the search recognises what it forbids.
    it "would recognise one" do
      expect("def exec(command)\n").to match(GENERIC[0])
      expect("system(command)").to match(GENERIC[2])
      expect("`docker service ls`").to match(GENERIC[5])
    end

    # The allowlist is data, and it is the complete list: an operation not in it
    # cannot be dispatched, which the unit spec proves; this pins the size so a
    # twelfth operation is a reviewed diff here as well.
    it "dispatches only the eleven operations M01 declares" do
      expect(SwarmExecutor::OPERATIONS.keys).to contain_exactly(
        "inspect_service", "create_service", "update_service_spec", "remove_service",
        "create_network", "inspect_network", "remove_network", "list_nodes", "inspect_node",
        "service_logs", "list_tasks"
      )
    end

    it "sends to the Engine only through EngineClient's three verbs" do
      source = code("app/executors/swarm_executor.rb")

      expect(source.scan(/client\.(\w+)\(/).flatten.uniq.sort).to eq(%w[delete get post])
      expect(source).not_to match(/curl|Open3|Socket/)
    end
  end

  # AC1 — nothing outside app/executors/ starts a Docker process or names the
  # socket. The fitness functions cover the socket and client libraries; this
  # covers the CLI and curl, which their pattern does not see.
  describe "the single boundary (AC1)" do
    ALLOWED = %w[app/executors/ spec/support/swarm_lab bin/swarm-lab lib/gates/swarm_lab.rb].freeze
    SELF = %w[
      spec/security/executor_isolation_spec.rb spec/security/docker_api_exposure_spec.rb
      lib/gates/fitness_functions.rb lib/gates/workspace_guardrail.rb
      config/architecture/fitness.yml config/architecture/docker-lab.yml
      spec/integration/swarm_bootstrap_lab_spec.rb spec/integration/swarm_init_verification.rb
      spec/integration/swarm_lab_spec.rb spec/integration/cluster_bootstrap_spec.rb
      spec/integration/swarm_executor_lab_spec.rb spec/unit/swarm_executor_spec.rb
      spec/unit/engine_client_spec.rb spec/unit/preflight_spec.rb spec/unit/system_probe_spec.rb
    ].freeze
    DOCKER_PROCESS = /(?:Open3\.\w+|system|spawn|exec)\(\s*["']docker["']|curl[^\n]*--unix-socket|`docker\s/

    it "starts a Docker process only from the declared boundary" do
      offenders = Dir.glob(File.join(ROOT, "{app,lib,config,bin}/**/*")).select { |p| File.file?(p) }
        .map { |p| p.delete_prefix("#{ROOT}/") }
        .reject { |p| SELF.include?(p) || ALLOWED.any? { |a| p.start_with?(a) } }
        .select { |p| code(p).match?(DOCKER_PROCESS) }

      expect(offenders).to be_empty, offenders.join("\n")
    end
  end

  # M01-93 — `fitness_self_referential` exempts a whole file from AF-02, and the
  # review of that Story showed what that costs: a planted
  # `SOCK = "/var/run/docker.sock"` inside `lib/gates/test_evidence.rb` left
  # AF-02 reporting `pass`. The exemption is the right list — those files talk
  # *about* Docker, they do not talk to it — but "does not talk to it" was an
  # assertion nobody made. This makes it.
  describe "the AF-02 exemptions still do not touch Docker (M01-93)" do
    def exempt_files
      YAML.safe_load_file(File.join(ROOT, "config/architecture/fitness.yml"))
        .fetch("fitness_self_referential").reject { |path| path.end_with?(".yml") }
    end

    # Narrower than AF-02 on purpose: naming `DOCKER_HOST` is why these files
    # are exempt, so naming it cannot be the offence. Reaching the socket, a
    # client library or the CLI is.
    TOUCHES = Regexp.union(
      %r{/var/run/docker\.sock}, /\bDocker::\w+/, DOCKER_PROCESS
    )

    it "is a list that exists and is not empty" do
      expect(exempt_files).not_to be_empty
    end

    it "holds no file that reaches the Engine" do
      offenders = exempt_files.select { |path| File.exist?(File.join(ROOT, path)) && code(path).match?(TOUCHES) }

      expect(offenders).to be_empty,
        "exempt from AF-02 and reaching Docker anyway:\n#{offenders.join("\n")}"
    end

    it "would recognise one" do
      expect(%(SOCK = "/var/run/docker.sock"\n)).to match(TOUCHES)
      expect(%(Docker::Service.create({})\n)).to match(TOUCHES)
      expect(%(ENV["DOCKER_HOST"]\n)).not_to match(TOUCHES)
    end
  end

  # AC2 — AF-01 and AF-02 evaluate real code and fail a controlled negative. The
  # checkers are run against a fixture tree rather than this one, so the negative
  # is planted rather than hoped for.
  describe "AF-01 and AF-02 against a planted violation (AC2)" do
    def with_fixture
      Dir.mktmpdir("opanel-af-") do |root|
        FileUtils.mkdir_p(File.join(root, "app/controllers"))
        FileUtils.mkdir_p(File.join(root, "app/jobs"))
        FileUtils.mkdir_p(File.join(root, "app/executors"))
        FileUtils.mkdir_p(File.join(root, "config/architecture"))
        FileUtils.cp(File.join(ROOT, "config/architecture/fitness.yml"),
File.join(root, "config/architecture/fitness.yml"))
        yield root
      end
    end

    # `run` answers one result per function, with `id` and `status` — the same
    # shape `spec/gates/fitness_functions_spec.rb` reads.
    def status_of(root, id)
      results = Opanel::Gates::FitnessFunctions.run(root: root,
        metadata_path: File.join(root, "config/architecture/fitness.yml"))
      results.find { |result| result.id == id }.status
    end

    it "AF-01 fails a public controller that names the socket" do
      with_fixture do |root|
        File.write(File.join(root, "app/controllers/deploys_controller.rb"),
          "class DeploysController\n  SOCK = \"/var/run/docker.sock\"\nend\n")

        expect(status_of(root, "AF-01")).to eq("fail")
      end
    end

    it "AF-02 fails an ordinary worker that holds a Docker client" do
      with_fixture do |root|
        File.write(File.join(root, "app/jobs/deploy_job.rb"),
          "class DeployJob\n  def perform = Docker::Service.create({})\nend\n")

        expect(status_of(root, "AF-02")).to eq("fail")
      end
    end

    it "AF-02 accepts the same reference inside app/executors/" do
      with_fixture do |root|
        File.write(File.join(root, "app/executors/thing.rb"),
          "class Thing\n  SOCK = \"/var/run/docker.sock\"\nend\n")

        expect(status_of(root, "AF-02")).to eq("pass")
      end
    end

    # What AF-02's pattern does not see, and this Story's own detector does: a
    # `docker` process or a curl to the socket started from a controller. Named
    # here so the gap is a known one with a test on it, not an unknown one.
    it "the CLI and curl gap is covered by this suite's own detector" do
      planted = "class DeploysController\n" \
                "  def go = Open3.capture3(\"docker\", \"service\", \"rm\", params[:id])\nend\n"

      expect(planted).to match(DOCKER_PROCESS)
      expect("system(\"curl --unix-socket /x/docker.sock http://localhost/info\")").to match(DOCKER_PROCESS)
    end
  end

  # AC10 — no public route and no published port. In M01 the executor is a
  # module inside the Control Plane process; what a test of configuration can
  # prove is that nothing routes to it and nothing publishes it.
  describe "no public route, no published port (AC10)" do
    it "has no route that reaches an executor" do
      routes = Rails.application.routes.routes.map { |r| [ r.path.spec.to_s, r.defaults[:controller].to_s ] }

      expect(routes.select { |path, controller| path.include?("executor") || controller.include?("executor") })
        .to be_empty
    end

    it "has no controller in app/executors/ and no executor in app/controllers/" do
      expect(Dir.glob(File.join(ROOT, "app/executors/**/*controller*"))).to be_empty
      expect(Dir.glob(File.join(ROOT, "app/controllers/**/*executor*"))).to be_empty
    end

    it "publishes no port for an executor in any stack or compose file" do
      files = Dir.glob(File.join(ROOT, "{config,deploy,ops,docker}/**/*.{yml,yaml}")) +
        Dir.glob(File.join(ROOT, "docker-compose*.yml")) + Dir.glob(File.join(ROOT, "*.yml"))

      offenders = files.select do |path|
        text = File.read(path)
        text.match?(/executor/i) && text.match?(/^\s*(ports|published):/)
      end

      expect(offenders).to be_empty
    end

    it "mounts the socket into nothing under config/" do
      offenders = Dir.glob(File.join(ROOT, "config/**/*.{yml,yaml,rb}")).select do |path|
        code(path.delete_prefix("#{ROOT}/")).match?(%r{/var/run/docker\.sock|docker\.sock:})
      end

      expect(offenders).to be_empty
    end
  end
end
