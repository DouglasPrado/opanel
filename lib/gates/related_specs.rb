# frozen_string_literal: true

module Opanel
  module Gates
    # Which specs a change makes relevant.
    #
    # `bin/test --changed` selected changed *spec* files and nothing else, and
    # exited 0 with "no spec file changed" whenever a commit touched only source.
    # The Local and Pre-commit Gates recorded that as `tests PASS` — so the one
    # commit shape where running the tests matters most was the shape where none
    # ran. Annex I §11.1 asks for the *related* tests, which is a different set.
    #
    # Three ways a file finds its specs, in order:
    #
    #   1. it is one;
    #   2. a spec is named after it — `app/jobs/application_job.rb` →
    #      `spec/unit/application_job_spec.rb`;
    #   3. its area has a known blast radius — a migration is judged by the
    #      Migration Gate suite, a gate script by spec/gates.
    #
    # Ruby under `app/` or `lib/` that matches none of the three is **uncovered**,
    # and uncovered is a failure rather than an empty selection: a source change
    # with nothing to run is not a suite that passed.
    module RelatedSpecs
      SPEC = %r{\Aspec/.*_spec\.rb\z}

      # Nothing RSpec can be selected for. The React tree, the browser journeys
      # and the prose have their own checks — bin/test:js, bin/test:e2e,
      # bin/lint — and pulling them in here would only make this selection lie
      # about what it covers.
      IGNORED = %r{
        \A(docs/|app/frontend/|e2e/|public/|node_modules/|vendor/|tmp/|log/|coverage/|assets/|\.claude/)
        | \.(md|markdown|tsx|ts|jsx|js|mjs|cjs|css|scss|json|lock|svg|png|jpe?g|ico|woff2?|txt|csv)\z
      }x

      # Fallbacks, used only when no spec is named after the file. Each entry is
      # the suite that would actually notice a change there.
      #
      # Deliberately by layer rather than a blanket `app/**`. A blanket entry
      # would mean nothing is ever uncovered, which turns the rule below into
      # decoration: a new directory nobody has mapped would quietly run the unit
      # suite and report green about a layer it never touched.
      AREAS = {
        %r{\Adb/migrate/} => %w[spec/gates/migration_gate_spec.rb spec/integration],
        %r{\Adb/} => %w[spec/integration],
        %r{\Aconfig/} => %w[spec/architecture spec/integration/boot_configuration_spec.rb],
        %r{\Alib/gates/} => %w[spec/gates],
        # The custom cops. They are proved the only way a lint rule can be —
        # planted with the violation and required to report it — and that is
        # spec/gates/lint_rules_spec.rb, not a unit spec named after the cop.
        %r{\Alib/rubocop/} => %w[spec/gates/lint_rules_spec.rb],
        %r{\Abin/} => %w[spec/gates],
        %r{\A\.githooks/} => %w[spec/gates],
        %r{\A\.github/} => %w[spec/gates/ci_pipeline_spec.rb],
        %r{\Aapp/models/} => %w[spec/unit spec/integration],
        %r{\Aapp/controllers/} => %w[spec/requests],
        %r{\Aapp/(jobs|commands|queries|operations|reconcilers|executors|providers)/} =>
          %w[spec/unit spec/integration],
        %r{\Aapp/policies/} => %w[spec/policies],
        %r{\Aapp/(helpers|views)/} => %w[spec/requests],
        %r{\Alib/opanel/} => %w[spec/unit],
        %r{\AGemfile} => %w[spec/architecture],
        %r{\A(Rakefile|config\.ru)\z} => %w[spec/architecture]
      }.freeze

      # Where "no spec at all" is a defect rather than a fact about the file.
      MUST_BE_COVERED = %r{\A(app|lib)/.*\.rb\z}

      Selection = Struct.new(:paths, :uncovered, keyword_init: true)

      module_function

      def for_changed(changed, root: Dir.pwd)
        paths = []
        uncovered = []

        changed.each do |file|
          next if file.match?(IGNORED)

          if file.match?(SPEC)
            paths << file
            next
          end

          related = by_name(file, root)
          related = by_area(file, root) if related.empty?

          if !related.empty?
            paths.concat(related)
          elsif file.match?(MUST_BE_COVERED)
            uncovered << file
          end
        end

        Selection.new(paths: paths.uniq.sort, uncovered: uncovered.uniq.sort)
      end

      def by_name(file, root)
        base = File.basename(file, File.extname(file))
        return [] if base.empty?

        Dir.glob(File.join(root, "spec/**/#{base}_spec.rb"))
          .map { |path| path.delete_prefix("#{root}/") }
      end

      def by_area(file, root)
        AREAS.select { |pattern, _| file.match?(pattern) }
          .values.flatten.uniq
          .select { |target| File.exist?(File.join(root, target)) }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  changed = $stdin.read.split("\n").map(&:strip).reject(&:empty?)
  selection = Opanel::Gates::RelatedSpecs.for_changed(changed)

  unless selection.uncovered.empty?
    warn "no spec is related to #{selection.uncovered.join(', ')}. A source change with nothing " \
         "to run is not a suite that passed: add the spec, or name the suite that covers it in " \
         "lib/gates/related_specs.rb AREAS."
    exit 3
  end

  puts selection.paths
end
