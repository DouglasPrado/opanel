# The PR stage, locally. Run with `bin/ci`.
#
# The job list comes from config/ci/jobs.yml — the same file the GitHub
# workflows schedule from — so this cannot drift into being a different, gentler
# pipeline. Adding a check to CI adds it here; there is nowhere to add one that
# only CI runs.
#
# `bin/ci-job <name>` runs a single job when that is all you need.

require_relative "../lib/gates/ci_pipeline"

CI.run do
  step "Setup", "bin/setup --skip-server"

  Opanel::Gates::CiPipeline.stage_jobs("pr").each do |job|
    step job.name, "bin/ci-job #{job.name}"
  end

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
