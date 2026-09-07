require "rails_helper"
require "open3"
require "yaml"

# The environment a clone gets. The properties that matter are that it can be
# re-run without fear, that a missing prerequisite says which one, and that a
# process dying is visible rather than silent.
RSpec.describe "local development environment", type: :integration do
  def run(*command, env: {})
    Open3.capture2e(env, *command, chdir: Rails.root.to_s)
  end

  describe "bin/setup" do
    let(:source) { Rails.root.join("bin/setup").read }

    it "is executable" do
      expect(File).to be_executable(Rails.root.join("bin/setup").to_s)
    end

    it "checks the workspace for a production credential before anything else" do
      guardrail = source.index("bin/workspace-guardrail")
      install = source.index("bundle install")

      expect(guardrail).to be < install,
        "if this machine holds a production credential, nothing else should run here at all"
    end

    it "checks every prerequisite the README declares" do
      %w[RUBY_VERSION node npm psql pg_isready].each do |prerequisite|
        expect(source).to include(prerequisite)
      end
    end

    it "gives every failure a remedy, not just a diagnosis" do
      # `fail_with` takes a problem *and* a remedy; a call site with only one
      # would hand the problem back unchanged.
      calls = source.scan(/fail_with\(/).length

      expect(calls).to be >= 5
      expect(source).to match(/def fail_with\(problem, remedy\)/)
      expect(source.scan(/remedy:/).length + source.scan(/^\s+"To fix/).length).to be >= 5
    end

    it "seeds, and says the seeds are synthetic" do
      expect(source).to include("db:seed")
      expect(source).to match(/synthetic/)
    end
  end

  # Every example above reads bin/setup's source, which cannot fail the way a
  # clean clone fails. The positive cycle — one command, then the same command
  # again — has to run somewhere disposable, and the CI runner's checkout is
  # exactly that. M00-06 AC1 and AC3.
  describe "the clean-clone cycle" do
    let(:pipeline) { YAML.safe_load_file(Rails.root.join("config/ci/jobs.yml")) }

    it "is executed in CI, twice, on a disposable checkout" do
      job = pipeline.dig("jobs", "setup")

      expect(job).not_to be_nil,
        "no CI job runs bin/setup: the single command the README promises is the one nothing executes"

      runs = job.fetch("commands").map(&:last).count { |command| command.include?("bin/setup") }

      expect(runs).to be >= 2,
        "running it once shows it works; running it twice is what shows it is idempotent (AC3)"
    end

    it "blocks a merge, so a broken setup cannot ship" do
      expect(pipeline.fetch("required_for_merge")).to include("setup")
    end

    it "is scheduled by the workflow" do
      expect(Rails.root.join(".github/workflows/ci.yml").read).to include("- setup")
    end
  end

  describe "bin/setup prerequisite failure" do
    # The failure this replaces is a stack trace forty lines into a build that
    # actually meant "PostgreSQL is not running".
    it "names the prerequisite and what to do about it" do
      # A PATH holding Ruby but not the tools Opanel needs. Stripping it to
      # /usr/bin would also strip Ruby, and the script would never get to run.
      path = [ RbConfig::CONFIG["bindir"], "/usr/bin", "/bin" ].join(":")

      output, status = run("bin/setup", "--skip-server", env: { "PATH" => path })

      expect(status).not_to be_success
      expect(output).to match(/bin\/setup failed/)
      expect(output).to match(/PostgreSQL|Node\.js/)
      expect(output).to match(/To fix:/)
      expect(output).to match(/brew|install/)
    end
  end

  describe "bin/dev" do
    let(:source) { Rails.root.join("bin/dev").read }

    it "is executable" do
      expect(File).to be_executable(Rails.root.join("bin/dev").to_s)
    end

    it "starts the web server, the worker and Vite" do
      expect(source).to include("bin/rails", "server")
      expect(source).to include("bin/jobs")
      expect(source).to include("bin/vite")
    end

    it "stops the others when one exits, so a dead process is not hidden" do
      expect(source).to match(/exited with status/)
      expect(source).to match(/stop_all/)
    end

    it "reports an occupied port with the process holding it" do
      expect(source).to include("lsof")
      expect(source).to match(/is held by/)
    end
  end

  # The failure this prevents is silent: the page loads, React never mounts, and
  # nothing in the server log says why. It only appears in a browser against the
  # Vite dev server, which is why it survived until a clean clone was tried.
  describe "development-mode rendering" do
    let(:layout) { Rails.root.join("app/views/layouts/application.html.erb").read }

    it "installs React Refresh before the Vite client" do
      refresh = layout.index("vite_react_refresh_tag")
      client = layout.index("vite_client_tag")

      expect(refresh).not_to be_nil,
        "without vite_react_refresh_tag, @vitejs/plugin-react cannot find its preamble"
      expect(refresh).to be < client
    end

    it "pins the Vite dev server to IPv4 loopback" do
      config = JSON.parse(Rails.root.join("config/vite.json").read)

      expect(config.dig("development", "host")).to eq("127.0.0.1"),
        "Vite binds IPv6-first; a browser resolving localhost to 127.0.0.1 then finds nothing"
    end
  end

  describe "seeds" do
    it "are idempotent: running them twice changes nothing the second time" do
      load Rails.root.join("db/seeds.rb")
      after_first = InfrastructureCheckpoint.count

      load Rails.root.join("db/seeds.rb")

      expect(InfrastructureCheckpoint.count).to eq(after_first)
    end

    it "contain no real data" do
      load Rails.root.join("db/seeds.rb")

      seeded = InfrastructureCheckpoint.where("name LIKE 'dev-%'").pluck(:name)

      expect(seeded).not_to be_empty
      expect(seeded).to all(start_with("dev-"))
      # Nothing that could be mistaken for a person or a customer.
      expect(seeded.join(" ")).not_to match(/@|\+\d{6,}|\b\d{11}\b/)
    end
  end

  describe "the README" do
    let(:readme) { Rails.root.join("README.md").read }

    it "documents the single command" do
      expect(readme).to include("bin/setup")
      expect(readme).to match(/That is the whole thing|single command/i)
    end

    it "documents the prerequisites with versions" do
      expect(readme).to match(/Ruby.*3\.2/)
      expect(readme).to match(/Node\.js.*20/)
      expect(readme).to match(/PostgreSQL.*16/)
    end

    it "documents how to reset and how to destroy the environment" do
      expect(readme).to include("bin/setup --reset")
      expect(readme).to include("bin/rails db:drop")
      expect(readme).to match(/Resetting and destroying/)
    end

    it "says no credential is needed to run locally" do
      expect(readme).to match(/No credential is needed to run locally/)
    end
  end
end
