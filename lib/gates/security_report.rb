# frozen_string_literal: true

require "json"
require "open3"
require "time"

require_relative "security_waivers"

# The Security Report of Annex D §24 — M00-10 AC8.
#
#   ruby lib/gates/security_report.rb tmp/security/security-report.json
#
# `bin/security --out` writes the gate's own result there first; this turns it
# into the artifact the table in Annex D names: **scanner and version, findings,
# severity, disposition/waiver.** A run's exit code is not a report — it says a
# scan happened and nothing about what was scanned, by which version of what, or
# which findings were accepted and by whom.
#
# The versions are asked for rather than declared, because the point of recording
# them is to know later what a green result actually covered: a scanner from
# before an advisory was published did not miss it, it could not have seen it.
module Opanel
  module Gates
    module SecurityReport
      TOOLS = {
        "gitleaks" => %w[gitleaks version],
        "bundler-audit" => %w[bundle exec bundle-audit version],
        "npm" => %w[npm --version],
        "brakeman" => %w[bundle exec brakeman --version]
      }.freeze

      module_function

      def version_of(command, root)
        stdout, stderr, status = Open3.capture3(*command, chdir: root)
        return "unavailable" unless status.success?

        (stdout + stderr).lines.first.to_s.strip
      rescue Errno::ENOENT
        "not installed"
      end

      def tools(root)
        TOOLS.map { |name, command| { name: name, version: version_of(command, root) } }
      end

      def git(root, *arguments)
        stdout, _stderr, status = Open3.capture3("git", *arguments, chdir: root)
        status.success? ? stdout.strip : nil
      end

      # A check that failed is a finding; its `reason` is what the scanner said.
      # Severity follows the policy of bin/security: a secret or a new
      # Critical/High blocks, so anything that turned the gate red is blocking.
      def findings(gate)
        gate.fetch("checks", []).reject { |check| check["result"] == "pass" }.map do |check|
          {
            scanner: check["check"],
            severity: check["result"] == "skip" ? "informational" : "blocking",
            disposition: check["result"] == "skip" ? "skipped" : "blocked the run",
            detail: check["reason"].to_s[0, 2000]
          }
        end
      end

      def build(gate, root)
        waivers = SecurityWaivers.load(File.join(root, "config/security/waivers.yml"))

        {
          report: "security",
          generated_at: Time.now.utc.iso8601,
          commit: git(root, "rev-parse", "HEAD"),
          branch: git(root, "rev-parse", "--abbrev-ref", "HEAD"),
          result: gate["result"],
          duration_ms: gate["duration_ms"],
          tools: tools(root),
          checks: gate.fetch("checks", []),
          findings: findings(gate),
          waivers: {
            active: waivers.active.map(&:to_h),
            expiring_soon: waivers.expiring_soon.map(&:to_h),
            expired: waivers.expired.map(&:to_h)
          }
        }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  destination = ARGV.fetch(0) { abort("usage: ruby lib/gates/security_report.rb <path>") }
  root = File.expand_path("../..", __dir__)

  gate =
    begin
      JSON.parse(File.read(destination))
    rescue Errno::ENOENT, JSON::ParserError => error
      abort("security-report: cannot read the gate result at #{destination}: #{error.class}")
    end

  File.write(destination, JSON.pretty_generate(Opanel::Gates::SecurityReport.build(gate, root)))
  puts "security report: #{destination}"
end
