# frozen_string_literal: true

require "yaml"
require "date"
require_relative "migration_gate"

module Opanel
  module Gates
    # Architecture fitness functions AF-01..AF-10 — Annex I §16.
    #
    # These turn documented invariants into properties a machine checks. They
    # exist because a hundred autonomous Stories will erode a boundary that only
    # a document defends, and nobody will be able to say which Story did it.
    #
    # Several pass **vacuously** today: there is no MCP adapter, no reconciler, no
    # serializer. That is deliberate and it is the point — the checker has to exist
    # *before* the code it governs, so the first file that crosses a boundary is
    # caught by the build rather than by a reviewer who happens to be paying
    # attention. Each one is proven by a planted violation, so a vacuous pass is
    # never mistaken for a working rule.
    module FitnessFunctions
      Violation = Struct.new(:function, :file, :line, :detail, :remedy, keyword_init: true) do
        def to_h = { function: function, file: file, line: line, detail: detail, remedy: remedy }
      end

      Result = Struct.new(:id, :rule, :status, :violations, :waived, :duration_ms, keyword_init: true) do
        def passed? = status == "pass"
        def to_h
          { id: id, rule: rule, status: status, waived: waived,
            duration_ms: duration_ms, violations: violations.map(&:to_h) }
        end
      end

      # Waiving one of these needs recorded human approval: they are security
      # controls, not layering preferences.
      HUMAN_APPROVAL_REQUIRED = %w[AF-02 AF-06 AF-07].freeze

      class InvalidWaiver < StandardError; end

      # A checker reads files and reports violations. Nothing else.
      class Base
        def initialize(root:, metadata:)
          @root = root
          @metadata = metadata
        end

        attr_reader :root, :metadata

        def id = raise(NotImplementedError)
        def rule = raise(NotImplementedError)
        def violations = raise(NotImplementedError)

        private

        def files(*globs)
          globs.flat_map { |glob| Dir.glob(File.join(root, glob)) }.select { |path| File.file?(path) }
        end

        def relative(path) = path.delete_prefix("#{root}/")

        def read(path)
          File.read(path, encoding: "BINARY").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        rescue SystemCallError
          ""
        end

        # Comments are not code. A rule that fires on a line explaining the rule
        # trains people to ignore it.
        def each_code_line(path)
          return enum_for(:each_code_line, path) unless block_given?

          read(path).each_line.with_index(1) do |line, number|
            stripped = line.strip
            next if stripped.start_with?("#", "//", "*", "/*")

            yield line, number
          end
        end

        def violation(path, line, detail, remedy)
          Violation.new(function: id, file: relative(path), line: line, detail: detail, remedy: remedy)
        end
      end

      # Anything that talks to the Docker Engine API.
      DOCKER_REFERENCE = /
        docker\.sock | \/var\/run\/docker | DOCKER_HOST |
        \bDocker::(Container|Service|Node|Swarm|Network|Secret|Image) |
        \brequire\s+["']docker | \bDockerode\b | \bdockerode\b |
        \bExcon\.new\(["']unix
      /x

      # AF-01 — a public controller may not reach Docker. It is one specific case
      # of AF-02, kept separate because it is the one that turns a boundary
      # violation into a route: a controller with a Docker client is a public HTTP
      # path to the socket.
      class Af01ControllersHaveNoDockerClient < Base
        def id = "AF-01"
        def rule = "Public controllers do not import a Docker client or socket adapter."

        def violations
          files("app/controllers/**/*.rb").flat_map do |path|
            each_code_line(path).filter_map do |line, number|
              next unless line.match?(DOCKER_REFERENCE)

              violation(path, number,
                "a controller references the Docker Engine API",
                "a controller records intent as an Operation; a Reconciler converges it through " \
                "app/executors/. A controller holding a Docker client is a public route to the socket.")
            end
          end
        end
      end

      # AF-02 — the Tier-0 invariant (Annex C §8).
      class Af02OnlyExecutorTouchesDocker < Base
        def id = "AF-02"
        def rule = "Only the Swarm Executor references docker.sock or a privileged Docker client."

        def violations
          allowed = metadata.fetch("docker_boundaries", [])
          # The checkers themselves contain the patterns by definition; excluding
          # them is not the same as granting the privilege, so it is a separate
          # list (see config/architecture/fitness.yml).
          self_referential = metadata.fetch("fitness_self_referential", [])

          files("app/**/*.rb", "lib/**/*.rb", "config/**/*.rb", "bin/*").flat_map do |path|
            relative_path = relative(path)
            next [] if allowed.any? { |boundary| relative_path.start_with?(boundary) }
            next [] if self_referential.include?(relative_path)

            each_code_line(path).filter_map do |line, number|
              next unless line.match?(DOCKER_REFERENCE)

              violation(path, number,
                "references the Docker Engine API outside the Swarm Executor",
                "only app/executors/ may hold that privilege (Annex C §8). Widening " \
                "config/architecture/fitness.yml `docker_boundaries` is a Tier-0 change and needs an ADR.")
            end
          end
        end
      end

      # AF-03 — a reconciler converges Actual State. It never rewrites intent.
      class Af03ReconcilersDoNotWriteIntent < Base
        def id = "AF-03"
        def rule = "Reconcilers do not write Desired State columns that hold user intent."

        def violations
          columns = metadata.fetch("user_intent_columns", []).flat_map { |entry| Array(entry["columns"]) }
          return [] if columns.empty?

          pattern = /\b(?:update|update!|assign_attributes|update_all|update_column|update_columns)\b/

          files("app/reconcilers/**/*.rb").flat_map do |path|
            each_code_line(path).filter_map do |line, number|
              next unless line.match?(pattern)

              touched = columns.find { |column| line.match?(/\b#{Regexp.escape(column)}\b\s*[:=]/) }
              next unless touched

              violation(path, number,
                "a reconciler writes `#{touched}`, which holds the user's approved intent",
                "converge Actual State instead. Platform Wins is the drift policy; adopting runtime " \
                "state is an explicit admin operation, not a reconciler side effect.")
            end
          end
        end
      end

      # AF-04 — the React tree has no server.
      class Af04ReactImportsNoServerCode < Base
        def id = "AF-04"
        def rule = "The React tree does not import database, Docker or other server-only code."

        SERVER_ONLY = %r{
          from\s+['"]node:[\w/]+['"] |
          from\s+['"](fs|path|child_process|net|dns|tls|crypto|os)['"] |
          from\s+['"](pg|dockerode|mysql2|ioredis)['"] |
          from\s+['"][^'"]*\.\./(config|db|lib)/[^'"]*['"] |
          require\(['"](fs|path|child_process|pg|dockerode)['"]\)
        }x

        def violations
          files("app/frontend/**/*.ts", "app/frontend/**/*.tsx").flat_map do |path|
            each_code_line(path).filter_map do |line, number|
              next unless line.match?(SERVER_ONLY)

              violation(path, number,
                "the React tree imports server-only code",
                "there is no build in which this works. If the browser needs the value, the server " \
                "sends it as an Inertia prop.")
            end
          end
        end
      end

      # AF-05 — MCP is a delivery channel, not a shortcut.
      class Af05McpGoesThroughApplicationLayer < Base
        def id = "AF-05"
        def rule = "The MCP adapter does not call the Swarm Executor directly."

        def violations
          files("app/mcp/**/*.rb", "lib/mcp/**/*.rb").flat_map do |path|
            each_code_line(path).filter_map do |line, number|
              next unless line.match?(/\bExecutors?::|app\/executors|SwarmExecutor/) || line.match?(DOCKER_REFERENCE)

              violation(path, number,
                "the MCP adapter reaches the executor directly",
                "the path is Agent → MCP → Application Layer → Command/Query → Operation → Reconciler → " \
                "Executor. Skipping the middle skips authorization and audit.")
            end
          end
        end
      end

      # AF-06 — the last automated line against a secret leaking.
      class Af06NoPlaintextSecretInOutput < Base
        def id = "AF-06"
        def rule = "Secret plaintext does not appear in serializers, logs or audit payloads."

        def violations
          fields = metadata.fetch("sensitive_field_names", [])
          return [] if fields.empty?

          pattern = /\b(#{fields.map { |field| Regexp.escape(field) }.join('|')})\b/

          files(
            "app/serializers/**/*.rb", "app/views/**/*.jbuilder",
            "app/audit/**/*.rb", "app/operations/**/*.rb", "app/jobs/**/*.rb"
          ).flat_map do |path|
            each_code_line(path).filter_map do |line, number|
              next unless line.match?(pattern)
              # An assignment *to* a redaction is the control working, not a leak.
              next if line.match?(/REDACT|\[REDACTED\]|Redaction|filter_parameters|sensitive_field_names/i)

              violation(path, number,
                "a sensitive field name reaches a serializer, log or audit payload",
                "reference a SecretVersion id instead. Revealing a secret is a separate, " \
                "permissioned, re-authenticated and audited action (Annex C §12).")
            end
          end
        end
      end

      # AF-07 — a mutation without a Policy is a mutation without authorization.
      class Af07CriticalMutationsHavePolicies < Base
        def id = "AF-07"
        def rule = "Critical mutations have a server-side authorization path."

        def violations
          mutations = metadata.fetch("critical_mutations", [])
          return [] if mutations.empty?

          mutations.filter_map do |mutation|
            policy_file = File.join(root, "app/policies", "#{underscore(mutation['policy'])}.rb")
            action = Regexp.escape(mutation["action"].to_s.delete("?"))
            next if File.exist?(policy_file) && read(policy_file).match?(/def\s+#{action}\??/)

            Violation.new(
              function: id,
              file: "app/policies/#{underscore(mutation['policy'])}.rb",
              line: nil,
              detail: "#{mutation['command']} is declared critical but " \
                      "#{mutation['policy']}##{mutation['action']} does not exist",
              remedy: "authorization is server-side and contextual, and every new mutation needs a " \
                      "negative test including a cross-team attempt (Annex C §7.3)."
            )
          end
        end

        private

        def underscore(name)
          name.to_s.gsub(/::/, "/").gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end
      end

      # AF-08 — an event nobody can correlate is an event nobody can use.
      class Af08EventsCarryCorrelation < Base
        def id = "AF-08"
        def rule = "Events and Operations carry correlation identifiers."

        REQUIRED = %w[correlation_id request_id operation_id].freeze

        def violations
          files("app/operations/**/*.rb", "app/events/**/*.rb").flat_map do |path|
            content = read(path)
            next [] if content.match?(/#{REQUIRED.join('|')}/)
            # A class that only declares associations carries nothing to correlate.
            next [] unless content.match?(/def\s+(call|perform|publish|emit)\b/)

            [ violation(path, nil,
              "an Operation or Event carries no correlation identifier",
              "at minimum request_id and operation_id, so a failure can be traced without " \
              "reproducing it (Annex I §19.2).") ]
          end
        end
      end

      # AF-09 — delegates to the Migration Gate rather than restating it.
      class Af09DestructiveMigrationsAreContractPhase < Base
        def id = "AF-09"
        def rule = "Known destructive migrations require a contract-phase marker or an ADR."

        def violations
          paths = Dir.glob(File.join(root, "db/migrate/*.rb"))

          MigrationGate.check_paths(paths)
            .select { |migration_violation| migration_violation.rule == "CONTRACT_PHASE" }
            .map do |migration_violation|
              Violation.new(
                function: id,
                file: relative(migration_violation.file),
                line: migration_violation.line,
                detail: migration_violation.message,
                remedy: migration_violation.remedy
              )
            end
        end
      end

      # AF-10 — a feature component that reimplements a primitive.
      class Af10FeatureDoesNotDuplicatePrimitive < Base
        def id = "AF-10"
        def rule = "A React feature does not duplicate an existing primitive without a waiver."

        def violations
          primitives = Dir.glob(File.join(root, "app/frontend/components/ui/*"))
            .select { |path| File.directory?(path) }
            .map { |path| File.basename(path) }
          return [] if primitives.empty?

          feature_dirs = Dir.glob(File.join(root, "app/frontend/components/features/*"))
            .select { |path| File.directory?(path) }

          feature_dirs.flat_map do |feature|
            Dir.glob(File.join(feature, "**/*.tsx")).filter_map do |path|
              name = File.basename(path, ".tsx")
              normalized = name.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase
              next unless primitives.include?(normalized)

              violation(path, nil,
                "a feature component named `#{name}` duplicates the `#{normalized}` primitive",
                "reuse it, compose it, or add a tested variant (Annex I §6.3). If it is genuinely " \
                "different, record a waiver in config/architecture/fitness.yml saying how.")
            end
          end
        end
      end

      ALL = [
        Af01ControllersHaveNoDockerClient,
        Af02OnlyExecutorTouchesDocker,
        Af03ReconcilersDoNotWriteIntent,
        Af04ReactImportsNoServerCode,
        Af05McpGoesThroughApplicationLayer,
        Af06NoPlaintextSecretInOutput,
        Af07CriticalMutationsHavePolicies,
        Af08EventsCarryCorrelation,
        Af09DestructiveMigrationsAreContractPhase,
        Af10FeatureDoesNotDuplicatePrimitive
      ].freeze

      module_function

      def today = Time.now.utc.to_date

      def load_metadata(path)
        return {} unless File.exist?(path)

        YAML.safe_load_file(path, permitted_classes: [ Date ]) || {}
      end

      def waivers(metadata)
        Array(metadata["waivers"]).map { |entry| validate_waiver!(entry) }
      end

      def validate_waiver!(entry)
        missing = %w[id function finding reason owner removal_story expires_at]
          .reject { |field| entry[field].to_s.strip != "" }

        unless missing.empty?
          raise InvalidWaiver,
            "fitness waiver #{entry['id'] || '(no id)'} is missing #{missing.join(', ')} — " \
            "a waiver without an owner, a deadline and a removal Story is a permanent exception"
        end

        begin
          Date.parse(entry["expires_at"].to_s)
        rescue ArgumentError
          raise InvalidWaiver, "fitness waiver #{entry['id']} has an unparseable expires_at"
        end

        if HUMAN_APPROVAL_REQUIRED.include?(entry["function"].to_s) && entry["approved_by"].to_s.strip.empty?
          raise InvalidWaiver,
            "fitness waiver #{entry['id']} silences #{entry['function']}, which is a security control " \
            "and needs recorded human approval (approved_by) — an agent may not waive it"
        end

        entry
      end

      # A violation is silenced only by a waiver that is still in date.
      def waived?(waiver_list, violation, on: today)
        waiver_list.any? do |waiver|
          waiver["function"] == violation.function &&
            violation.file.to_s.include?(waiver["finding"].to_s) &&
            Date.parse(waiver["expires_at"].to_s) >= on
        end
      end

      def run(root:, metadata_path: nil, on: today)
        metadata_path ||= File.join(root, "config/architecture/fitness.yml")
        metadata = load_metadata(metadata_path)
        waiver_list = waivers(metadata)

        ALL.map do |checker_class|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          checker = checker_class.new(root: root, metadata: metadata)
          found = checker.violations
          waived, blocking = found.partition { |violation| waived?(waiver_list, violation, on: on) }
          duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

          Result.new(
            id: checker.id, rule: checker.rule,
            status: blocking.empty? ? "pass" : "fail",
            violations: blocking, waived: waived.length, duration_ms: duration
          )
        end
      end
    end
  end
end
