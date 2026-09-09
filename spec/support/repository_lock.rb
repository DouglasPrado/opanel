require "fileutils"

module Opanel
  module Gates
    # Serializes access to the repository's own working tree.
    #
    # `spec/gates` and `spec/security` prove a gate by planting a real,
    # tracked change — a staged secret, a lint offence, a probe file — and a
    # full-tree/history scan (`gitleaks dir .`, `gitleaks git .`) reads that
    # same tree. Under `bin/test --parallel` those two things run in
    # different worker *processes* at the same instant, and the working tree
    # is one filesystem shared by all of them: a worker's transient probe
    # becomes a "leak" the scanning worker never planted.
    #
    # `TEST_ENV_NUMBER`-based namespacing (spec/support/concurrency.rb)
    # cannot isolate this, because the contended resource is not a name a
    # worker picks — it is the one checkout every worker shares. An advisory
    # file lock does: whichever side holds it has exclusive use of the tree
    # until it releases, so a plant-then-scan example and a scan-the-whole-
    # tree example never observe each other's half-finished state.
    module RepositoryLock
      LOCK_PATH = File.expand_path("../../tmp/gate/repository.lock", __dir__)

      # Plain mutual exclusion, not a read/write lock. Two probes staging
      # *different* files looked independent, but `git add`/`git rm --cached`
      # both take `.git/index.lock` and do not retry on contention — two of
      # them racing (one from spec/gates/gate_scripts_spec.rb, one from
      # spec/gates/ci_pipeline_spec.rb) can make one silently no-op, so the
      # file it meant to stage never lands and the check under test passes
      # for the wrong reason. Every writer and every full-tree reader
      # (spec/security/security_scan_spec.rb's scan, this file's own
      # production boot with eager loading) needs the same single lock.
      def self.exclusive
        FileUtils.mkdir_p(File.dirname(LOCK_PATH))
        File.open(LOCK_PATH, File::CREAT | File::RDWR) do |file|
          file.flock(File::LOCK_EX)
          begin
            yield
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      end
    end
  end
end
