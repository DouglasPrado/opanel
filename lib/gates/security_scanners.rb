# frozen_string_literal: true

require "json"

module Opanel
  module Gates
    # The scanners' own results, normalised — Annex D §24, M00-10 AC8.
    #
    # The Security Report used to be built from the gate's check list: one entry
    # per tool, `severity: "blocking"`. That describes the *run*, not what it
    # found. It cannot name an advisory, a package or a severity, so nothing
    # downstream could count Critical and High — the Merge Gate asked for exactly
    # that and got zero from every report, including the reports of runs that
    # found something.
    #
    # So each scanner's machine-readable output is preserved (bin/security writes
    # it to tmp/security/scanners/) and parsed into one finding per vulnerability.
    #
    # Two fields, deliberately separate:
    #
    #   * `severity` is the scanner's, unmodified. It is what a reader and the
    #     Merge Gate count.
    #   * `blocking` is this repository's policy about that severity, with the
    #     reason attached. A policy that is not blocking today is recorded as such
    #     with the decision that made it so — never by quietly downgrading the
    #     severity, which would make the report disagree with the scanner.
    module SecurityScanners
      DIRECTORY = "tmp/security/scanners"

      # Which file each check leaves behind, so a check that ran without
      # producing one is visible rather than absent.
      OUTPUTS = {
        "secret-scan" => "gitleaks.json",
        "secret-scan-staged" => "gitleaks.json",
        "secret-scan-history" => "gitleaks-history.json",
        "bundler-audit" => "bundler-audit.json",
        "npm-audit" => "npm-audit.json",
        "brakeman" => "brakeman.json"
      }.freeze

      # Annex C §21.1: a secret blocks, always; a new Critical or High in a
      # dependency blocks; static analysis is informative until M01 (M00-10).
      BLOCKING_SEVERITIES = %w[critical high].freeze

      STATIC_ANALYSIS_POLICY =
        "informational in M00: static analysis is reported and tracked, and blocks from M01 " \
        "(bin/security, M00-10). The severity above is the scanner's own."

      module_function

      def path(root, name) = File.join(root, DIRECTORY, name)

      def read_json(root, name)
        raw = File.read(path(root, name))
        raw.strip.empty? ? nil : JSON.parse(raw)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      # One finding per leak. The value never travels: rule, file and line only
      # (bin/security runs gitleaks with --redact, and this does not copy the
      # field either).
      def gitleaks(document, source)
        Array(document).map do |leak|
          {
            scanner: "gitleaks",
            source: source,
            id: leak["RuleID"].to_s,
            subject: "#{leak['File']}:#{leak['StartLine']}",
            severity: "critical",
            blocking: true,
            title: leak["Description"].to_s,
            disposition: "a secret that reached the repository is compromised and needs rotation"
          }
        end
      end

      def bundler_audit(document)
        Array(document&.dig("results")).map do |result|
          advisory = result["advisory"] || {}
          gem = result["gem"] || {}
          severity = normalise(advisory["criticality"])

          {
            scanner: "bundler-audit",
            source: "bundler-audit.json",
            id: (advisory["cve"] || advisory["ghsa"] || advisory["id"]).to_s,
            subject: "#{gem['name']} #{gem['version']}",
            severity: severity,
            blocking: BLOCKING_SEVERITIES.include?(severity),
            title: advisory["title"].to_s.lines.first.to_s.strip,
            disposition: result["type"].to_s
          }
        end
      end

      def npm_audit(document)
        Array(document&.dig("vulnerabilities")&.values).flat_map do |entry|
          severity = normalise(entry["severity"])
          advisories = Array(entry["via"]).select { |via| via.is_a?(Hash) }

          # A package whose vulnerability comes only from a transitive path has
          # no advisory object of its own; it is still a finding.
          sources = advisories.empty? ? [ nil ] : advisories

          sources.map do |advisory|
            {
              scanner: "npm-audit",
              source: "npm-audit.json",
              id: advisory ? "GHSA/#{advisory['source']}" : "transitive",
              subject: "#{entry['name']} #{entry['range']}",
              severity: advisory ? normalise(advisory["severity"]) : severity,
              blocking: BLOCKING_SEVERITIES.include?(advisory ? normalise(advisory["severity"]) : severity),
              title: advisory ? advisory["title"].to_s : "vulnerable via #{Array(entry['via']).join(', ')}",
              disposition: entry["fixAvailable"] ? "a fix is available" : "no fix available"
            }
          end
        end
      end

      # Brakeman reports confidence, not severity. Mapped rather than invented,
      # and the mapping is stated so a reader is not left guessing what "high"
      # meant.
      CONFIDENCE = { "High" => "high", "Medium" => "medium", "Weak" => "low" }.freeze

      def brakeman(document)
        Array(document&.dig("warnings")).map do |warning|
          severity = CONFIDENCE.fetch(warning["confidence"].to_s, "medium")

          {
            scanner: "brakeman",
            source: "brakeman.json",
            id: warning["check_name"].to_s,
            subject: "#{warning['file']}:#{warning['line']}",
            severity: severity,
            blocking: false,
            title: "#{warning['warning_type']}: #{warning['message']}",
            disposition: STATIC_ANALYSIS_POLICY
          }
        end
      end

      def normalise(value)
        found = value.to_s.downcase
        found.empty? ? "unknown" : found
      end

      # Every check that ran, against the output it should have left behind.
      #
      # A scanner whose structured result is missing or unreadable is itself a
      # finding: a report that cannot enumerate what a tool found does not get to
      # report zero on its behalf.
      def findings(gate, root)
        Array(gate["checks"]).flat_map do |check|
          name = check["check"].to_s
          next unmeasured(check) unless OUTPUTS.key?(name)
          next [] if check["result"] == "skip"

          document = read_json(root, OUTPUTS.fetch(name))
          next [ unreadable(name, OUTPUTS.fetch(name)) ] if document.nil?

          parse(name, document)
        end
      end

      def parse(name, document)
        case name
        when "secret-scan", "secret-scan-staged" then gitleaks(document, "gitleaks.json")
        when "secret-scan-history" then gitleaks(document, "gitleaks-history.json")
        when "bundler-audit" then bundler_audit(document)
        when "npm-audit" then npm_audit(document)
        when "brakeman" then brakeman(document)
        else []
        end
      end

      def unreadable(name, file)
        {
          scanner: name,
          source: file,
          id: "scanner-output-missing",
          subject: File.join(DIRECTORY, file),
          severity: "high",
          blocking: true,
          title: "#{name} ran but left no readable result at #{File.join(DIRECTORY, file)}",
          disposition: "a report that cannot enumerate a scanner's findings is not a report of zero " \
                       "findings — re-run bin/security"
        }
      end

      # Checks with no scanner behind them — the waiver, allowlist and dependency
      # gates. They have no per-vulnerability output, so a red one is carried as
      # its own finding rather than dropped.
      def unmeasured(check)
        return [] if check["result"] == "pass"

        [ {
          scanner: check["check"].to_s,
          source: "bin/security",
          id: check["check"].to_s,
          subject: check["check"].to_s,
          severity: check["result"] == "skip" ? "informational" : "high",
          blocking: check["result"] != "skip",
          title: check["reason"].to_s[0, 2000],
          disposition: check["result"] == "skip" ? "skipped" : "blocked the run"
        } ]
      end
    end
  end
end
