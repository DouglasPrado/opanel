require "spec_helper"
require "open3"
require "fileutils"
require "securerandom"

# A lint rule nobody proved can fail is decoration. Each critical rule is planted
# with a violation and must reject it, and is then shown to accept the compliant
# form so it is not simply refusing everything.
#
# The probes are written into the repository on purpose: a rule that only applies
# to `app/frontend/**` cannot be exercised from a temp directory. They are removed
# in an `ensure`, and their directories are git-ignored.
RSpec.describe "lint rules" do
  LINT_PROBE_ROOT = File.expand_path("../..", __dir__)

  def run(*command)
    Open3.capture2e(*command, chdir: LINT_PROBE_ROOT)
  end

  # ESLint only applies the frontend ruleset to files under app/frontend/.
  def with_frontend_probe(source, extension: "tsx")
    directory = File.join(LINT_PROBE_ROOT, "app/frontend/.lint-probe")
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "probe-#{SecureRandom.hex(4)}.#{extension}")
    File.write(path, source)

    yield path.delete_prefix("#{LINT_PROBE_ROOT}/")
  ensure
    FileUtils.rm_rf(directory)
  end

  def with_ruby_probe(source)
    directory = File.join(LINT_PROBE_ROOT, "tmp/lint-probe")
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "probe_#{SecureRandom.hex(4)}.rb")
    File.write(path, source)

    yield path.delete_prefix("#{LINT_PROBE_ROOT}/")
  ensure
    FileUtils.rm_rf(directory)
  end

  describe "import boundary — app/frontend may not reach server-only code" do
    it "rejects a Node built-in import" do
      output, status = with_frontend_probe(<<~TSX) { |path| run("npx", "eslint", "--no-warn-ignored", path) }
        import { readFileSync } from 'node:fs';

        export function probe() {
          return readFileSync('/etc/passwd');
        }
      TSX

      expect(status).not_to be_success, "the import boundary did not reject a Node built-in:\n#{output}"
      expect(output).to include("no-restricted-imports")
      expect(output).to match(/server-only|Node built-in/)
    end

    it "rejects importing from the Rails tree" do
      output, status = with_frontend_probe(<<~TSX) { |path| run("npx", "eslint", "--no-warn-ignored", path) }
        import config from '../../../config/vite.json';

        export const probe = config;
      TSX

      expect(status).not_to be_success, "the import boundary did not reject a Rails-tree import:\n#{output}"
      expect(output).to include("no-restricted-imports")
    end

    it "accepts an import inside the frontend tree" do
      output, status = with_frontend_probe(<<~TSX) { |path| run("npx", "eslint", "--no-warn-ignored", path) }
        import { cn } from '@/lib/utils';

        export function probe(): string {
          return cn('a', 'b');
        }
      TSX

      expect(status).to be_success, output
    end
  end

  describe "test selectors — a CSS class is not a selector (Annex D §11.1)" do
    it "rejects locator('.class')" do
      probe = ->(path) { run("npx", "eslint", "--no-warn-ignored", path) }

      output, status = with_frontend_probe(<<~TSX, extension: "ts", &probe)
        export function probe(page: { locator: (selector: string) => unknown }) {
          return page.locator('.deploy-button');
        }
      TSX

      expect(status).not_to be_success, "a CSS-class selector was accepted:\n#{output}"
      expect(output).to include("no-restricted-syntax")
      expect(output).to include("data-testid")
    end

    it "rejects querySelector('.class')" do
      probe = ->(path) { run("npx", "eslint", "--no-warn-ignored", path) }

      output, status = with_frontend_probe(<<~TSX, extension: "ts", &probe)
        export function probe(root: Element) {
          return root.querySelector('.service-row');
        }
      TSX

      expect(status).not_to be_success, output
      expect(output).to include("no-restricted-syntax")
    end

    it "rejects getElementsByClassName" do
      probe = ->(path) { run("npx", "eslint", "--no-warn-ignored", path) }

      output, status = with_frontend_probe(<<~TSX, extension: "ts", &probe)
        export function probe(root: Element) {
          return root.getElementsByClassName('service-row');
        }
      TSX

      expect(status).not_to be_success, output
    end

    it "accepts a role or test-id selector" do
      probe = ->(path) { run("npx", "eslint", "--no-warn-ignored", path) }

      output, status = with_frontend_probe(<<~TSX, extension: "ts", &probe)
        interface Page {
          getByRole: (role: string, options?: { name?: string }) => unknown;
          getByTestId: (id: string) => unknown;
        }

        export function probe(page: Page) {
          return [page.getByRole('button', { name: 'Deploy' }), page.getByTestId('service-row')];
        }
      TSX

      expect(status).to be_success, output
    end
  end

  describe "Opanel/SilentRescue — a broad rescue may not answer success" do
    def rubocop(path)
      run("bundle", "exec", "rubocop", "--format", "simple", "--only", "Opanel/SilentRescue", path)
    end

    it "rejects a broad rescue that returns true" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          def deploy
            perform_the_work
          rescue StandardError
            true
          end
        end
      RUBY

      expect(status).not_to be_success, "a silent rescue was accepted:\n#{output}"
      expect(output).to include("Opanel/SilentRescue")
    end

    it "rejects a bare rescue that returns a literal" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          def deploy
            perform_the_work
          rescue
            :ok
          end
        end
      RUBY

      expect(status).not_to be_success, output
    end

    it "accepts a broad rescue that re-raises" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          def deploy
            perform_the_work
          rescue StandardError => error
            record(error)
            raise
          end
        end
      RUBY

      expect(status).to be_success, output
    end

    it "accepts a broad rescue that returns a classified failure" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          def check
            perform_the_work
          rescue StandardError => error
            classify(error)
          end
        end
      RUBY

      expect(status).to be_success, output
    end
  end

  describe "Opanel/UnclassifiedError — raise a class, not a sentence" do
    def rubocop(path)
      run("bundle", "exec", "rubocop", "--format", "simple", "--only", "Opanel/UnclassifiedError", path)
    end

    it "rejects raising a bare message" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          def call
            raise "service is not ready"
          end
        end
      RUBY

      expect(status).not_to be_success, "an unclassified error was accepted:\n#{output}"
      expect(output).to include("Opanel/UnclassifiedError")
    end

    it "accepts raising a classified error" do
      output, status = with_ruby_probe(<<~RUBY) { |path| rubocop(path) }
        class Probe
          Failure = Class.new(StandardError)

          def call
            raise Failure, "service is not ready"
          end
        end
      RUBY

      expect(status).to be_success, output
    end
  end

  describe "Suppression Gate — a silenced rule names the Story or ADR" do
    it "rejects a suppression with no reference" do
      output, status = with_ruby_probe(<<~RUBY) { |path| run("bin/suppression-gate", path) }
        class Probe
          # rubocop:disable Metrics/AbcSize
          def call
            :ok
          end
          # rubocop:enable Metrics/AbcSize
        end
      RUBY

      expect(status).not_to be_success, "an unjustified suppression was accepted:\n#{output}"
      expect(output).to include("SUPPRESSION_JUSTIFIED")
      expect(output).to include("docs/engineering/lint-suppressions.md")
    end

    it "rejects an unjustified eslint-disable" do
      output, status = with_frontend_probe(<<~TSX, extension: "ts") { |path| run("bin/suppression-gate", path) }
        // eslint-disable-next-line no-restricted-imports
        export const probe = 1;
      TSX

      expect(status).not_to be_success, output
    end

    it "accepts a suppression that names a Story" do
      output, status = with_ruby_probe(<<~RUBY) { |path| run("bin/suppression-gate", path) }
        class Probe
          # rubocop:disable Metrics/AbcSize -- M01-14: the state machine reads worse split
          def call
            :ok
          end
          # rubocop:enable Metrics/AbcSize
        end
      RUBY

      expect(status).to be_success, output
    end

    it "accepts a reason written on the line above" do
      output, status = with_ruby_probe(<<~RUBY) { |path| run("bin/suppression-gate", path) }
        class Probe
          # ADR-0002: ULIDs are 26 characters, the length check is intentional.
          # rubocop:disable Metrics/AbcSize
          def call
            :ok
          end
          # rubocop:enable Metrics/AbcSize
        end
      RUBY

      expect(status).to be_success, output
    end

    it "points at the convention document, which exists" do
      expect(File.exist?(File.join(LINT_PROBE_ROOT, "docs/engineering/lint-suppressions.md"))).to be(true)
    end
  end
end
