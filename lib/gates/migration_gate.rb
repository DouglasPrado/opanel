# frozen_string_literal: true

# Migration Gate — Annex I §8.2.
#
# Reads migration source and refuses the three failures that expand-contract is
# meant to prevent: a migration that cannot be undone and has no plan, a
# destructive change smuggled in without a contract phase, and an index build that
# would lock a hot table in production.
#
# It works on source text on purpose. It has to run in the Pre-commit Gate, before
# the migration has ever touched a database, and it has to say which file and which
# rule failed rather than raise from inside Active Record.
#
# Loaded directly by bin/migration-gate and by the specs; `lib/gates` is excluded
# from autoloading in config/application.rb so requiring it here is safe.
module Opanel
  module Gates
    class MigrationGate
      Violation = Struct.new(:rule, :file, :line, :message, :remedy, keyword_init: true) do
        def to_h
          { rule: rule, file: file, line: line, message: message, remedy: remedy }
        end
      end

      # Markers a migration uses to declare intent. They are the only way to pass a
      # rule that would otherwise fail, and each one forces a human-readable reason
      # into the file itself.
      PHASE_MARKER = /^\s*#\s*migration-phase:\s*(expand|contract|data)\s*$/
      CONTRACT_REF_MARKER = /^\s*#\s*migration-contract-ref:\s*(\S.*)$/
      FORWARD_FIX_MARKER = /^\s*#\s*migration-forward-fix:\s*(\S.*)$/
      INDEX_REVIEW_MARKER = /^\s*#\s*migration-index-review:\s*(\S.*)$/

      # Operations that destroy data or a contract another running version may still
      # depend on. Removing them is only safe in the contract phase, after the code
      # that used the old shape is gone.
      DESTRUCTIVE_OPERATIONS = %w[
        drop_table
        drop_join_table
        remove_column
        remove_columns
        remove_reference
        remove_belongs_to
        rename_table
        rename_column
      ].freeze

      DESTRUCTIVE_SQL = /\b(DROP\s+(TABLE|COLUMN)|ALTER\s+TABLE\s+\S+\s+DROP)\b/i

      # Commands Active Record cannot invert on its own inside `def change`.
      IRREVERSIBLE_IN_CHANGE = %w[execute change_column].freeze

      RULES = {
        "REVERSIBILITY" => "A migration is reversible, or declares a forward-fix plan.",
        "CONTRACT_PHASE" => "A destructive change happens in the contract phase and names the decision that allows it.",
        "INDEX_SAFETY" => "An index build on a table that may already hold rows is reviewed or built concurrently."
      }.freeze

      def self.check_paths(paths)
        paths.flat_map { |path| new(path).violations }
      end

      def initialize(path)
        @path = path.to_s
        @source = File.read(@path)
        @lines = @source.lines
      end

      attr_reader :path

      def violations
        [ reversibility_violation, *contract_phase_violations, *index_safety_violations ].compact
      end

      private

      attr_reader :source, :lines

      def reversibility_violation
        return nil if forward_fix?
        return nil if defines_down?

        if defines_up? && !defines_down?
          return violation(
            "REVERSIBILITY",
            line_of(/^\s*def\s+up\b/),
            "defines `up` without `down`",
            "add `def down`, or declare `# migration-forward-fix: <how a bad rollout is corrected forward>`"
          )
        end

        offending = irreversible_command_in_change
        return nil unless offending

        violation(
          "REVERSIBILITY",
          offending.last,
          "`#{offending.first}` inside `def change` cannot be reverted automatically",
          "wrap it in `reversible do |dir|`, add `def down`, or declare `# migration-forward-fix: <plan>`"
        )
      end

      def contract_phase_violations
        destructive_lines.filter_map do |operation, line_number|
          next if contract_phase? && contract_ref?

          reason =
            if !contract_phase?
              "is missing `# migration-phase: contract`"
            else
              "is missing `# migration-contract-ref: <ADR-NNNN or Story id>`"
            end

          violation(
            "CONTRACT_PHASE",
            line_number,
            "`#{operation}` destroys a column, table or name and #{reason}",
            "run the destructive step only after the code depending on the old shape is gone, " \
            "then declare `# migration-phase: contract` and `# migration-contract-ref: <decision>`"
          )
        end
      end

      def index_safety_violations
        index_lines.filter_map do |statement, line_number|
          concurrent = statement.include?("algorithm: :concurrently")

          if concurrent && !source.match?(/^\s*disable_ddl_transaction!/)
            next violation(
              "INDEX_SAFETY",
              line_number,
              "`algorithm: :concurrently` requires `disable_ddl_transaction!`",
              "add `disable_ddl_transaction!` to the migration class; PostgreSQL refuses a " \
              "concurrent index build inside a transaction"
            )
          end

          next if concurrent || index_reviewed?

          violation(
            "INDEX_SAFETY",
            line_number,
            "adds an index without a review note and without `algorithm: :concurrently`",
            "build it with `algorithm: :concurrently` plus `disable_ddl_transaction!`, or declare " \
            "`# migration-index-review: <why this build is safe — new table, small table, maintenance window>`"
          )
        end
      end

      def destructive_lines
        found = []

        each_code_line do |line, number|
          DESTRUCTIVE_OPERATIONS.each do |operation|
            found << [ operation, number ] if line.match?(/(^|[^\w.])#{operation}\b/)
          end

          found << [ "execute (destructive SQL)", number ] if line.match?(DESTRUCTIVE_SQL)
        end

        found
      end

      def index_lines
        found = []

        each_code_line do |line, number|
          next unless line.match?(/(^|[^\w.])add_index\b/) ||
            (line.match?(/(^|[^\w.])add_reference\b/) && !line.match?(/index:\s*false/))

          found << [ line, number ]
        end

        found
      end

      def irreversible_command_in_change
        return nil unless defines_change?

        result = nil

        each_code_line do |line, number|
          next if result

          IRREVERSIBLE_IN_CHANGE.each do |command|
            result = [ command, number ] if line.match?(/(^|[^\w.])#{command}\b/)
          end

          # `remove_column :table, :column` is only invertible when the column type
          # is given, and `drop_table` only when a block rebuilds the table.
          if line.match?(/(^|[^\w.])remove_column\b/) && line.count(",") < 2
            result = [ "remove_column without a type", number ]
          end

          if line.match?(/(^|[^\w.])drop_table\b/) && !line.include?(" do")
            result = [ "drop_table without a block", number ]
          end
        end

        result
      end

      # Comments carry the markers, so rules that look for operations must not match
      # a commented-out line, and `reversible do ... end` blocks are explicitly
      # handled by the author.
      def each_code_line
        inside_reversible = 0

        lines.each_with_index do |line, index|
          number = index + 1
          stripped = line.strip

          next if stripped.start_with?("#")

          if stripped.match?(/^reversible\s+do\b/)
            inside_reversible += 1
            next
          end

          if inside_reversible.positive?
            inside_reversible -= 1 if stripped == "end"
            next
          end

          yield line, number
        end
      end

      def defines_change? = source.match?(/^\s*def\s+change\b/)
      def defines_up? = source.match?(/^\s*def\s+up\b/)
      def defines_down? = source.match?(/^\s*def\s+down\b/)
      def forward_fix? = source.match?(FORWARD_FIX_MARKER)
      def contract_phase? = source.lines.any? { |line| line.match(PHASE_MARKER)&.captures&.first == "contract" }
      def contract_ref? = source.match?(CONTRACT_REF_MARKER)
      def index_reviewed? = source.match?(INDEX_REVIEW_MARKER)

      def line_of(pattern)
        index = lines.index { |line| line.match?(pattern) }
        index ? index + 1 : nil
      end

      def violation(rule, line, message, remedy)
        Violation.new(rule: rule, file: path, line: line, message: message, remedy: remedy)
      end
    end
  end
end
