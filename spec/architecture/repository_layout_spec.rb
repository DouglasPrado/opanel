require "spec_helper"
require "pathname"

# The directory layout is a contract, not a convention: every following Milestone
# places code by boundary, and the fitness functions of M00-13 resolve their rules
# against these paths. Renaming or removing one of them must break the build here
# first, with a message that says which boundary went missing.
RSpec.describe "Repository layout" do
  ROOT = Pathname.new(File.expand_path("../..", __dir__)).freeze

  BACKEND_BOUNDARIES = %w[
    app/commands
    app/queries
    app/policies
    app/operations
    app/reconcilers
    app/executors
    app/providers
  ].freeze

  FRONTEND_DIRECTORIES = %w[
    app/frontend/components/ui
    app/frontend/components/shared
    app/frontend/components/features
    app/frontend/components/layouts
    app/frontend/pages
    app/frontend/hooks
    app/frontend/lib
    app/frontend/types
  ].freeze

  describe "backend boundaries (Annex I 4.1)" do
    BACKEND_BOUNDARIES.each do |boundary|
      it "keeps #{boundary}/ present and documented" do
        directory = ROOT.join(boundary)

        expect(directory).to be_directory,
          "missing boundary directory #{boundary}/ — see docs/annexes/I-engineering-playbook-quality-gates.md 4.1"

        readme = directory.join("README.md")
        expect(readme).to be_file,
          "#{boundary}/README.md is missing — every boundary declares its responsibility and its prohibitions"
        expect(readme.read).to match(/## Prohibitions/),
          "#{boundary}/README.md must state what may not live there"
      end
    end
  end

  describe "frontend hierarchy (Annex I 6.1)" do
    FRONTEND_DIRECTORIES.each do |directory|
      it "keeps #{directory}/ present" do
        expect(ROOT.join(directory)).to be_directory,
          "missing frontend directory #{directory}/ — the ui/shared/features/layouts categories must stay visible"
      end
    end
  end

  describe "frozen stack decision (SC-01)" do
    it "has no separate api/web application directories" do
      %w[apps/api apps/web].each do |forbidden|
        expect(ROOT.join(forbidden)).not_to exist,
          "#{forbidden}/ contradicts the single Rails application decided in SC-01"
      end
    end

    it "has no Next.js configuration file" do
      matches = Dir.glob(ROOT.join("next.config.*").to_s) +
        Dir.glob(ROOT.join("app/frontend/**/next.config.*").to_s)

      expect(matches).to be_empty,
        "Next.js configuration found (#{matches.join(', ')}); the UI is Rails + Inertia + React"
    end

    it "does not declare next as a JavaScript dependency" do
      package_json = ROOT.join("package.json")
      next unless package_json.exist?

      manifest = JSON.parse(package_json.read)
      declared = manifest.values_at("dependencies", "devDependencies").compact.flat_map(&:keys)

      expect(declared).not_to include("next"),
        "package.json declares next; the UI is Rails + Inertia + React"
    end
  end
end
