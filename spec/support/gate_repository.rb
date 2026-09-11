require "fileutils"
require "open3"
require "tmpdir"

module Opanel
  module Gates
    # Real tools and configuration, private files and Git index. Dependencies
    # are shared read-only by convention; probes never modify dependency trees.
    module GateRepository
      def self.with(source)
        Dir.mktmpdir("opanel-gate-fixture-") do |directory|
          output, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z",
chdir: source)
          raise "cannot enumerate gate fixture inputs" unless status.success?

          output.split("\0").uniq.each do |path|
            next if %w[node_modules vendor/bundle].include?(path)

            from = File.join(source, path)
            next unless File.file?(from) || File.symlink?(from)

            to = File.join(directory, path)
            FileUtils.mkdir_p(File.dirname(to))
            if File.symlink?(from)
              File.symlink(File.readlink(from), to)
            else
              FileUtils.cp(from, to, preserve: true)
            end
          end
          %w[node_modules vendor/bundle].each do |path|
            from = File.join(source, path)
            next unless File.directory?(from)

            to = File.join(directory, path)
            FileUtils.mkdir_p(File.dirname(to))
            File.symlink(File.realpath(from), to)
          end
          system("git", "init", "-q", chdir: directory, exception: true)
          File.write(File.join(directory, ".git/info/exclude"), "/vendor/bundle\n/node_modules\n")
          [ %w[git config maintenance.auto false], %w[git config gc.auto 0],
            %w[git config user.email fixture@example.invalid],
            %w[git config user.name Fixture], %w[git add -A],
            %w[git commit -q -m fixture], %w[git branch -M main] ].each do |command|
            _out, error, result = Open3.capture3(*command, chdir: directory)
            raise error unless result.success?
          end
          yield directory
        end
      end
    end
  end
end
