require "spec_helper"
require "pathname"

# The inventory is what makes the Reuse Gate verifiable: "no equivalent component
# existed" is checked against it. An inventory that drifts from disk is worse than
# none, because it is trusted and wrong. These examples fail when the three
# sources — the directories, the gallery registry and INVENTORY.md — disagree.
RSpec.describe "component inventory" do
  FRONTEND = Pathname.new(File.expand_path("../../app/frontend", __dir__)).freeze
  COMPONENTS = FRONTEND.join("components").freeze
  INVENTORY = COMPONENTS.join("INVENTORY.md").freeze
  REGISTRY = COMPONENTS.join("features/gallery/registry.tsx").freeze

  CATEGORIES = %w[ui shared layouts].freeze

  def components_on_disk
    CATEGORIES.flat_map do |category|
      directory = COMPONENTS.join(category)
      next [] unless directory.directory?

      directory.children.select(&:directory?).map { |path| [ category, path.basename.to_s ] }
    end
  end

  def inventory_entries
    # Every row of every component table starts with the component name in
    # backticks, in the first cell.
    INVENTORY.read.lines.filter_map do |line|
      match = line.match(/\A\|\s*`([a-z0-9-]+)`\s*\|/)
      match && match[1]
    end
  end

  def registry_entries
    REGISTRY.read.scan(/name:\s*'([a-z0-9-]+)',\s*category:\s*'(ui|shared|layouts)'/m)
      .map { |name, category| [ category, name ] }
  end

  it "exists and is not empty" do
    expect(INVENTORY).to be_file
    expect(INVENTORY.size).to be > 2_000
  end

  it "lists every component that exists on disk" do
    missing = components_on_disk.map(&:last) - inventory_entries

    expect(missing).to be_empty,
      "these components exist under app/frontend/components/ but are not in INVENTORY.md: #{missing.sort.inspect}"
  end

  it "does not list a component that no longer exists" do
    disk = components_on_disk.map(&:last)
    upstream_only = INVENTORY.read.split("## Available upstream, not imported").last.to_s
    upstream = upstream_only.scan(/`([a-z0-9-]+)`/).flatten

    stale = inventory_entries - disk - upstream

    expect(stale).to be_empty,
      "INVENTORY.md still lists #{stale.sort.inspect}, which is no longer on disk"
  end

  it "renders every component in the gallery" do
    missing = components_on_disk - registry_entries

    expect(missing).to be_empty,
      "these components are not rendered by the gallery registry: #{missing.sort.inspect}"
  end

  it "does not render a component the gallery no longer has" do
    stale = registry_entries - components_on_disk

    expect(stale).to be_empty,
      "the gallery registry renders #{stale.sort.inspect}, which is not on disk"
  end

  it "gives every entry a responsibility, props, and a 'do not use' guidance" do
    # Only the imported-component tables. The "available upstream" table is a
    # deliberate two-column list of what was *not* imported.
    imported_section = INVENTORY.read.split("## Available upstream, not imported").first
    rows = imported_section.lines.select { |line| line.match?(/\A\|\s*`[a-z0-9-]+`\s*\|/) }
    incomplete = rows.filter_map do |row|
      cells = row.split("|").map(&:strip).reject(&:empty?)
      name = cells.first
      # name, responsibility, props, use when, do not use when
      cells.length < 5 || cells[1..4].any? { |cell| cell.length < 8 } ? name : nil
    end

    expect(incomplete).to be_empty,
      "these inventory entries are missing responsibility, props, or usage guidance: #{incomplete.inspect}"
  end

  it "keeps the four category directories of Annex I §6.1 visible" do
    %w[ui shared features layouts].each do |category|
      expect(COMPONENTS.join(category)).to be_directory
    end
  end

  it "records the components that exist upstream but were not imported" do
    expect(INVENTORY.read).to include("## Available upstream, not imported")
    expect(INVENTORY.read).to match(/Rebuilding one of these is a review finding/)
  end

  describe "security" do
    let(:sources) do
      Dir.glob(COMPONENTS.join("**/*.{ts,tsx}")).reject { |path| path.include?("/features/gallery/") }
    end

    it "has no component that reads or writes the clipboard" do
      offending = sources.select do |path|
        File.read(path).match?(/navigator\s*\.\s*clipboard|document\.execCommand\s*\(\s*['"]copy/)
      end

      expect(offending).to be_empty,
        "copying a value — a secret above all — must be an explicit, confirmed user action (doc 10 §28): " \
        "#{offending.map { |path| path.delete_prefix("#{FRONTEND}/") }.inspect}"
    end

    it "imported no secret-input component, and says so" do
      secret_inputs = components_on_disk.map(&:last).grep(/password|secret|otp|credit/)

      expect(secret_inputs).to be_empty
      expect(INVENTORY.read).to include("No secret-input component was imported")
    end

    it "detects a clipboard call if one is ever added" do
      # The check has to be able to fail. This plants the violation against the
      # same matcher the real assertion uses.
      planted = "await navigator.clipboard.writeText(secret)"

      expect(planted).to match(/navigator\s*\.\s*clipboard|document\.execCommand\s*\(\s*['"]copy/)
    end
  end
end
