# frozen_string_literal: true

require "json"

module Opanel
  module Gates
    # Every entry of the secret-scan allowlist carries a written reason — M00-10
    # AC4, Annex C §21.1.
    #
    # This was asserted by counting `#` characters in the file, which a single
    # paragraph at the top satisfies for any number of entries. An unexplained
    # allowlist entry is indistinguishable from a real secret somebody hid, and
    # the way one gets added is by pasting a pattern under an existing comment
    # that was about something else.
    #
    # So each entry is matched to the comment block immediately above it: the
    # nearest `#` line, with nothing but other entries of the same block between.
    # A comment that covers several entries covers them all — they were added
    # together, for one reason.
    #
    # Runnable directly, so it can be a check without booting anything:
    #   ruby lib/gates/secret_allowlist.rb
    module SecretAllowlist
      CONFIG = "config/security/gitleaks.toml"

      Violation = Struct.new(:file, :line, :entry, :message, :remedy, keyword_init: true) do
        def to_h = { file: file, line: line, entry: entry, message: message, remedy: remedy }
      end

      ARRAY_START = /^\s*(paths|regexes)\s*=\s*\[/
      ARRAY_END = /^\s*\]/
      COMMENT = /^\s*#/
      ENTRY = /^\s*(?:'''|"""|'|")(.+?)(?:'''|"""|'|")\s*,?\s*$/

      module_function

      def check(root = Dir.pwd)
        path = File.join(root, CONFIG)
        return [ missing(path) ] unless File.exist?(path)

        violations = []
        inside = nil
        explained = false

        File.readlines(path).each_with_index do |line, index|
          if (start = line[ARRAY_START, 1])
            inside = start
            explained = false
            next
          end

          next if inside.nil?

          if line.match?(ARRAY_END)
            inside = nil
            next
          end

          # A blank line ends the run a comment explains. Appending under an
          # unrelated group is how an entry ends up "justified" by a reason
          # written about something else.
          if line.strip.empty?
            explained = false
            next
          end

          if line.match?(COMMENT)
            explained = true
            next
          end

          entry = line[ENTRY, 1]
          next if entry.nil?

          next if explained

          violations << Violation.new(
            file: CONFIG, line: index + 1, entry: entry,
            message: "the #{inside} entry `#{entry}` carries no reason",
            remedy: "write, above it, why this path or value cannot contain a real secret. " \
                    "An unexplained allowlist entry is indistinguishable from a secret somebody hid."
          )
        end

        violations
      end

      def missing(path)
        Violation.new(
          file: CONFIG, line: nil, entry: nil,
          message: "#{path} does not exist",
          remedy: "the secret scan has no configuration; a scan that runs on defaults is not the " \
                  "scan this repository declares"
        )
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("../..", __dir__)
  format = ARGV.include?("--json") || ARGV.include?("--format=json") ? "json" : "text"
  violations = Opanel::Gates::SecretAllowlist.check(root)

  if format == "json"
    puts JSON.pretty_generate(
      check: "secret-allowlist",
      result: violations.empty? ? "pass" : "fail",
      violations: violations.map(&:to_h)
    )
  elsif violations.empty?
    puts "secret-allowlist: PASS (every entry carries a reason)"
  else
    violations.each do |violation|
      puts "secret-allowlist: FAIL #{violation.file}:#{violation.line}"
      puts "  #{violation.message}"
      puts "  remedy: #{violation.remedy}"
    end
  end

  exit(violations.empty? ? 0 : 1)
end
