# frozen_string_literal: true

# Workspace guardrail — Annex H §3.2.
#
# **No production credential may exist in the autonomous workspace.** Not in the
# environment, not in a file, not in a git-ignored `.env`. The rule is checked by
# a command rather than trusted, because the whole point of the autonomous loop is
# that nobody is watching while it runs.
#
# It looks for two things:
#
#   1. Credential *shapes* — an AWS access key, a private key block, a bearer
#      token, a database URL with a password — anywhere in the environment or in
#      the workspace's own files.
#   2. Credential *destinations* — a variable naming production, a remote Docker
#      host, a database URL pointing somewhere that is not this machine. A
#      perfectly-shaped credential to a staging box is fine; the same credential
#      to production is not.
#
# It reports the variable or the file and the pattern, never the value.
module Opanel
  module Gates
    class WorkspaceGuardrail
      Finding = Struct.new(:rule, :source, :detail, :remedy, keyword_init: true) do
        def to_h = { rule: rule, source: source, detail: detail, remedy: remedy }
      end

      RULE = "NO_PRODUCTION_CREDENTIAL"
      RULE_DESCRIPTION = "No production credential exists in the workspace (Annex H §3.2)."

      # Value shapes that are credentials wherever they appear.
      CREDENTIAL_SHAPES = {
        "aws-access-key" => /\b(AKIA|ASIA)[A-Z0-9]{16}\b/,
        "private-key" => /-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/,
        "github-token" => /\bgh[pousr]_[A-Za-z0-9]{16,}\b/,
        "slack-token" => /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/,
        "stripe-live-key" => /\bsk_live_[A-Za-z0-9]{16,}\b/,
        "google-service-account" => /"type":\s*"service_account"/,
        "jwt" => /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/
      }.freeze

      # A variable whose *name* says production and which carries a value.
      # Matched on underscore-separated segments: PRODUCTION_DB_PASSWORD and
      # PROD_API_KEY count, REPRODUCIBLE_BUILD does not.
      PRODUCTION_NAME = /(?:\A|_)(PROD|PRODUCTION)(?:_|\z)/i

      # Anything that is not this machine.
      LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 0.0.0.0 host.docker.internal db postgres].freeze

      # Environment variables that legitimately mention production without being a
      # credential — RAILS_ENV=production is a mode, not a secret.
      NAME_ALLOWLIST = %w[RAILS_ENV RACK_ENV NODE_ENV OPANEL_RENDER_ERROR_PAGES].freeze

      SCANNED_FILES = %w[.env .env.local .env.production .env.development .envrc
                         config/master.key config/credentials.yml.enc kubeconfig].freeze

      def initialize(env: ENV, root: Dir.pwd)
        @env = env
        @root = root
      end

      def findings
        environment_findings + file_findings + docker_findings
      end

      private

      attr_reader :env, :root

      def environment_findings
        env.flat_map do |name, value|
          next [] if NAME_ALLOWLIST.include?(name)
          next [] if value.to_s.strip.empty?

          shape_findings(name, value.to_s, source: "environment: #{name}") +
            production_name_findings(name, value.to_s) +
            remote_database_findings(name, value.to_s)
        end
      end

      def file_findings
        SCANNED_FILES.flat_map do |relative|
          path = File.join(root, relative)
          next [] unless File.file?(path)

          if relative == "config/master.key" || relative == "config/credentials.yml.enc"
            next [ Finding.new(
              rule: RULE,
              source: relative,
              detail: "Rails credentials file present",
              remedy: "Opanel reads configuration from the environment. Delete it; an unused master key " \
                      "in the workspace is exactly the secret Annex H §3.2 forbids."
            ) ]
          end

          content = read(path)
          shape_findings(relative, content, source: "file: #{relative}") +
            content.each_line.flat_map do |line|
              name, value = line.split("=", 2)
              next [] if value.nil?

              production_name_findings(name.to_s.strip, value.to_s.strip, source: "file: #{relative}") +
                remote_database_findings(name.to_s.strip, value.to_s.strip, source: "file: #{relative}")
            end
        end
      end

      # The Docker socket is the platform's most dangerous handle. A DOCKER_HOST
      # pointing anywhere but this machine means the workspace can reach a cluster
      # it must never reach (Annex H §12.2).
      def docker_findings
        host = env["DOCKER_HOST"].to_s.strip
        return [] if host.empty?
        return [] if host.start_with?("unix://") || LOCAL_HOSTS.any? { |local| host.include?(local) }

        [ Finding.new(
          rule: RULE,
          source: "environment: DOCKER_HOST",
          detail: "points at a Docker daemon that is not local",
          remedy: "The autonomous workspace uses the disposable Swarm Lab (bin/swarm-lab). " \
                  "Unset DOCKER_HOST or point it at the lab."
        ) ]
      end

      def shape_findings(_name, value, source:)
        CREDENTIAL_SHAPES.filter_map do |shape, pattern|
          next unless value.match?(pattern)

          Finding.new(
            rule: RULE,
            source: source,
            detail: "matches the shape of a #{shape}",
            remedy: "Remove it from the workspace and rotate it — a credential that reached a " \
                    "workspace is compromised, not merely misplaced."
          )
        end
      end

      def production_name_findings(name, value, source: "environment: #{name}")
        return [] if NAME_ALLOWLIST.include?(name)
        return [] unless name.match?(PRODUCTION_NAME)
        return [] if value.strip.empty?

        [ Finding.new(
          rule: RULE,
          source: source,
          detail: "a variable naming production carries a value",
          remedy: "The autonomous workspace has no production access. Unset it."
        ) ]
      end

      def remote_database_findings(name, value, source: "environment: #{name}")
        return [] unless value.match?(%r{\A[a-z][a-z0-9+.\-]*://})
        return [] unless value.match?(%r{://[^\s/@]+:[^\s/@]+@})

        host = value[%r{://[^\s/@]+@([^\s/:?]+)}, 1].to_s
        return [] if host.empty? || LOCAL_HOSTS.include?(host)

        [ Finding.new(
          rule: RULE,
          source: source,
          detail: "a connection URL carries a password and points at #{host}, which is not this machine",
          remedy: "Point it at the local database, or unset it. Never echo the value."
        ) ]
      end

      def read(path)
        File.read(path, encoding: "BINARY").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      rescue SystemCallError
        ""
      end
    end
  end
end
