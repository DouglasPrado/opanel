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

        each_code_line do |line, number, _in_reversible|
          DESTRUCTIVE_OPERATIONS.each do |operation|
            found << [ operation, number ] if line.match?(/(^|[^\w.])#{operation}\b/)
          end

          found << [ "execute (destructive SQL)", number ] if line.match?(DESTRUCTIVE_SQL)
        end

        found
      end

      def index_lines
        found = []

        each_code_line do |line, number, _in_reversible|
          next unless line.match?(/(^|[^\w.])add_index\b/) ||
            (line.match?(/(^|[^\w.])add_reference\b/) && !line.match?(/index:\s*false/))

          found << [ line, number ]
        end

        found
      end

      def irreversible_command_in_change
        return nil unless defines_change?

        result = nil

        each_code_line do |line, number, in_reversible|
          # This is the one rule `reversible` legitimately answers: the author has
          # written the inverse by hand.
          next if result || in_reversible

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

      # Opens a block that has to be closed by `end`. A `{ ... }` block does not,
      # and a modifier `if` does not either — both would unbalance the depth.
      BLOCK_OPENER = /
        \bdo\b\s*(\|[^|]*\|)?\s*\z |
        \A(if|unless|case|begin|while|until|for|def|class|module)\b
      /x

      # Comments carry the markers, so rules that look for operations must not match
      # a commented-out line.
      #
      # `reversible do ... end` is yielded like any other code, with a flag saying
      # so. Skipping the block entirely — which is what this did — hid a
      # `drop_table` from the contract-phase rule and an `add_index` from the
      # index-safety rule: writing `reversible` made a destructive migration
      # invisible to the two rules that are not about reversibility at all. Only
      # `irreversible_command_in_change` may read the flag.
      #
      # The depth is tracked rather than assumed. The previous version decremented
      # on the first `end` at any nesting level, so `reversible do |dir| dir.up
      # do ... end end` left the checker convinced it was still inside the block
      # for the rest of the file.
      def each_code_line
        return enum_for(:each_code_line) unless block_given?

        depth = 0
        reversible_at = nil

        lines.each_with_index do |line, index|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          reversible_at = depth if reversible_at.nil? && stripped.match?(/(^|[^\w.])reversible\s+do\b/)

          yield line, index + 1, !reversible_at.nil?

          depth += 1 if stripped.match?(BLOCK_OPENER)

          next unless stripped == "end" || stripped.start_with?("end ", "end.", "end)")

          depth -= 1
          reversible_at = nil if reversible_at && depth <= reversible_at
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
