# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"
require "fileutils"

module Opanel
  module Gates
    # Test inputs exclude only administrative artifacts. Stories, boundaries,
    # configuration, executable code and tests always invalidate a result.
    module TestEvidence
      ADMINISTRATIVE = %r{\Adocs/implementation/M\d{2}/(?:tasks\.json|(?:reports|review)/[^/]+\.md)\z}
      module_function

      def git(root, *args)
        output, error, status = Open3.capture3("git", *args, chdir: root)
        raise error unless status.success?

        output
      end

      def identity(root, revision: nil)
        entries = if revision
          git(root, "ls-tree", "-rz", revision).split("\0").map do |entry|
            attributes, path = entry.split("\t", 2)
            mode, _type, oid = attributes.split
            [ path, mode, oid ]
          end
        else
          git(root, "ls-files", "--cached", "--others", "--exclude-standard",
"-z").split("\0").uniq.filter_map do |path|
            absolute = File.join(root, path)
            next unless File.file?(absolute) || File.symlink?(absolute)

            data = File.symlink?(absolute) ? File.readlink(absolute) : File.binread(absolute)
            mode = File.symlink?(absolute) ? "120000" : (File.executable?(absolute) ? "100755" : "100644")
            [ path, mode, Digest::SHA1.hexdigest("blob #{data.bytesize}\0".b + data.b) ]
          end
        end
        Digest::SHA256.hexdigest(entries.reject { |path, _mode, _oid| path.match?(ADMINISTRATIVE) }.sort.to_json)
      end

      def context
        Digest::SHA256.hexdigest([ RUBY_DESCRIPTION, RUBY_PLATFORM,
          ENV.fetch("RAILS_ENV", "test"), ENV.fetch("OPANEL_TEST_DATABASE_NAME", "opanel_test"),
          ENV["DATABASE_URL"], ENV["DOCKER_HOST"], ENV["DOCKER_CONTEXT"], ENV["TEST_ENV_NUMBER"] ].to_json)
      end

      def expand(paths, root)
        paths.flat_map do |path|
          absolute = File.join(root, path)
          File.directory?(absolute) ? Dir.glob(File.join(absolute, "**/*_spec.rb")) : [ absolute ]
        end.map { |path| path.delete_prefix("#{root}/") }.uniq.sort
      end

      def records(root)
        Dir.glob(File.join(root, "tmp/test-results/runs/*.json")).sort.filter_map do |path|
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          nil
        end
      end

      def valid?(record, identity:, context: nil)
        record["input_identity"] == identity && record["inputs_stable"] == true &&
          (context.nil? || record["context"] == context) && record["tests"].to_i.positive? &&
          record["result"] == "pass" && record["failures"].to_i.zero? &&
          record["errors"].to_i.zero? && record["skipped"].to_i.zero?
      end

      # A newer failure for a requested file invalidates an older pass for that
      # file. A failing probe in another selection cannot erase a complete run.
      def uncovered(records, required, identity:, context: nil, fast: false, parallel: nil, fresh: false)
        candidates = records.select do |record|
          record["input_identity"] == identity && (context.nil? || record["context"] == context) &&
            (parallel.nil? || record["parallel"] == parallel) && (!record["fast"] || fast) &&
            (!fresh || Time.parse(record.fetch("finished_at")) > Time.now - 3600)
        end.sort_by { |record| record.fetch("finished_at", "") }
        latest = {}
        candidates.each { |record| Array(record["spec_files"]).each { |path| latest[path] = record } }
        required.reject { |path| latest[path] && valid?(latest[path], identity: identity, context: context) }
      rescue ArgumentError
        required
      end

      def write(path, record)
        FileUtils.mkdir_p(File.dirname(path))
        temporary = "#{path}.#{Process.pid}.tmp"
        File.write(temporary, JSON.pretty_generate(record))
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary) if temporary
      end
    end
  end
end
