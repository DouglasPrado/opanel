require "spec_helper"
require "pathname"

# The gates reference these templates by stable path and the reports are only
# useful if their sections are actually there. Removing a section must break here,
# not silently produce an unreviewable report three Milestones later.
RSpec.describe "Operational templates" do
  TEMPLATES_ROOT = Pathname.new(File.expand_path("../../docs/templates", __dir__)).freeze

  REQUIRED_SECTIONS = {
    # "Status" is an ADR field, not a heading — ADR-0001..0003 already carry it in
    # the front matter plus a bold line, and the template keeps that shape.
    "ADR.md" => [
      "**Status:**", "## Context", "## Decision", "## Consequences",
      "## Alternatives considered", "## Affected docs", "## Affected modules",
      "## When an ADR is required"
    ],
    "STORY_REPORT.md" => [
      "## Resultado", "## Arquivos alterados", "## Schema / API / Events",
      "## Decisões locais", "## Testes executados", "## Quality Gates",
      "## Acceptance Criteria", "## Dependências novas", "## Pendências / conflitos"
    ],
    "MILESTONE_REPORT.md" => [
      "## Stories", "## Quality", "## Findings", "## Resultado funcional",
      "## Blocked", "## Dependências novas", "## Conflitos de especificação",
      "## Human acceptance requested"
    ],
    "DEPENDENCY_JUSTIFICATION.md" => [
      "Problema resolvido", "Alternativas avaliadas", "Por que não bastam",
      "Maintenance", "Security", "License", "Impacto de longo prazo", "Lockfile"
    ],
    "REVIEW_FINDINGS.md" => [
      "## Severities and blocking policy", "## Review dimensions", "## Findings",
      "## Contagem"
    ],
    "BLOCKER.md" => [
      "## Valid qualifiers", "## Attempt policy", "### Diagnóstico reproduzível",
      "### O que destravaria"
    ],
    "COMMIT_CONVENTION.md" => [
      "## Format", "## Good", "## Bad", "## Rules"
    ],
    "README.md" => [
      "## Prohibited content", "## Rules that apply to all templates"
    ]
  }.freeze

  # ADR-0003 fixes the roles: only the orchestrator writes a Milestone verdict.
  FORBIDDEN_IN_MILESTONE_REPORT = %w[READY_FOR_HUMAN_ACCEPTANCE].freeze

  REQUIRED_SECTIONS.each do |file, sections|
    describe file do
      let(:content) { TEMPLATES_ROOT.join(file).read }

      it "exists" do
        expect(TEMPLATES_ROOT.join(file)).to be_file
      end

      sections.each do |section|
        it "documents #{section.inspect}" do
          expect(content).to include(section),
            "docs/templates/#{file} lost the section #{section.inspect}; the gates and reports depend on it"
        end
      end

      it "states the prohibition on sensitive content" do
        expect(content).to match(/[Ss]ensitive content|Prohibited content/),
          "docs/templates/#{file} must state that no report, review or evidence may carry sensitive content"
      end
    end
  end

  describe "MILESTONE_REPORT.md handoff status (SC-15)" do
    let(:content) { TEMPLATES_ROOT.join("MILESTONE_REPORT.md").read }

    it "instructs the implementer to emit Status: READY_FOR_REVIEW" do
      expect(content).to include("Status: READY_FOR_REVIEW")
    end

    FORBIDDEN_IN_MILESTONE_REPORT.each do |forbidden|
      it "does not instruct the implementer to emit #{forbidden}" do
        offending = content.lines.grep(/^\s*Status: #{Regexp.escape(forbidden)}/)

        expect(offending).to be_empty,
          "the implementer never declares #{forbidden}; only the orchestrator moves a Milestone forward"
      end
    end
  end

  describe "blocking qualifiers" do
    let(:content) { TEMPLATES_ROOT.join("BLOCKER.md").read }

    %w[BLOCKED_FOR_PRODUCT_DECISION BLOCKED_FOR_HUMAN_APPROVAL BLOCKED_EXTERNAL_DEPENDENCY].each do |qualifier|
      it "documents #{qualifier}" do
        expect(content).to include(qualifier)
      end
    end
  end

  describe "review severities" do
    let(:content) { TEMPLATES_ROOT.join("REVIEW_FINDINGS.md").read }

    %w[Critical High Medium Low].each do |severity|
      it "documents the #{severity} policy" do
        expect(content).to match(/\*\*#{severity}\*\*/),
          "docs/templates/REVIEW_FINDINGS.md must state the blocking policy of #{severity}"
      end
    end
  end

  # AC9. A gate that says "something is missing" leaves the reader to work out
  # what to write; one that names the template does not.
  describe "the gates" do
    ROOT_FOR_GATES = Pathname.new(File.expand_path("../..", __dir__)).freeze

    {
      "lib/gates/post_commit.rb" => %w[docs/templates/STORY_REPORT.md docs/templates/REVIEW_FINDINGS.md],
      "lib/gates/stop_gate.rb" => %w[
        docs/templates/STORY_REPORT.md docs/templates/MILESTONE_REPORT.md
        docs/templates/REVIEW_FINDINGS.md docs/templates/BLOCKER.md
      ]
    }.each do |gate, templates|
      templates.each do |template|
        it "#{gate} points at #{File.basename(template)} by stable path" do
          expect(ROOT_FOR_GATES.join(gate).read).to include(template)
          expect(ROOT_FOR_GATES.join(template)).to exist,
            "the gate names a template that is not there"
        end
      end
    end
  end
end
