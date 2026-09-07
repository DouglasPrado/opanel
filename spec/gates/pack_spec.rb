require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/gates/pack"
require_relative "../../lib/gates/json_schema"

# The Implementation Pack's state, and the rules that keep it trustworthy.
#
# The loop's memory is this repository rather than the conversation (Annex H §5),
# so every rule below exists because breaking it costs a session: a Story file
# that is not there, a dependency that names nothing, a cycle that never returns,
# a `done` with no commit behind it, a block nobody can reproduce.
RSpec.describe Opanel::Gates::Pack do
  PACK_ROOT = File.expand_path("../..", __dir__)

  # A throwaway pack: one Milestone, whatever Stories the example needs.
  def with_pack(stories, milestone: "M99", story_files: true)
    Dir.mktmpdir do |root|
      directory = File.join(root, "docs/implementation", milestone)
      FileUtils.mkdir_p(File.join(directory, "stories"))

      if story_files
        stories.each do |story|
          next unless story["file"]

          path = File.join(directory, story["file"])
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "# #{story['id']}\n")
        end
      end

      File.write(File.join(directory, "tasks.json"), JSON.generate(
        milestone: milestone, name: "Probe", status: "in_progress",
        dependencies: [], stories: stories
      ))

      yield File.join(directory, "tasks.json"), root
    end
  end

  def story(id, **overrides)
    {
      "id" => id, "file" => "stories/#{id}.md", "status" => "pending",
      "dependsOn" => [], "attempts" => 0, "required" => true
    }.merge(overrides.transform_keys(&:to_s))
  end

  def rules_for(stories, **options)
    with_pack(stories, **options) do |path, root|
      described_class.validate(path, root).map(&:rule)
    end
  end

  # AC1.
  describe "the real pack" do
    it "validates every Milestone of this repository" do
      output, status = Open3.capture2e("bin/pack", "validate", chdir: PACK_ROOT)

      expect(status).to be_success, output
      expect(output).to match(/pack: PASS \(15 milestone\(s\)\)/)
    end

    it "checks a schema that is versioned, so an editor can read it too" do
      schema = JSON.parse(File.read(File.join(PACK_ROOT, "config/pack/tasks.schema.json")))

      expect(schema.dig("properties", "stories", "items", "properties", "status", "enum"))
        .to contain_exactly("pending", "ready", "in_progress", "review", "fix_required", "done", "blocked")
    end
  end

  # The schema was called the contract and then not executed: a hand-written
  # check covered five of its rules and every other constraint validated clean.
  describe "the schema, applied" do
    # A document written verbatim, so a payload can violate the *shape* rather
    # than only the values `with_pack` allows.
    def violations_for(document)
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99")
        FileUtils.mkdir_p(File.join(directory, "stories"))
        File.write(File.join(directory, "stories/M99-01.md"), "# M99-01\n")
        File.write(File.join(directory, "tasks.json"), JSON.generate(document))

        described_class.validate(File.join(directory, "tasks.json"), root)
      end
    end

    def pack_with(story_overrides = {}, **overrides)
      {
        "milestone" => "M99", "name" => "Probe", "status" => "in_progress",
        "dependencies" => [], "stories" => [ {
          "id" => "M99-01", "file" => "stories/M99-01.md", "status" => "pending",
          "dependsOn" => [], "attempts" => 0, "required" => true
        }.merge(story_overrides) ]
      }.merge(overrides)
    end

    it "accepts the shape the schema declares" do
      expect(violations_for(pack_with)).to be_empty
    end

    {
      "a property the schema does not declare" => [ { "owner" => "someone" }, /unknown property/ ],
      "an attempts count below the minimum" => [ { "attempts" => -3 }, /below the minimum/ ],
      "an attempts count of the wrong type" => [ { "attempts" => "one" }, /should be integer/ ],
      "a required flag of the wrong type" => [ { "required" => "yes" }, /should be boolean/ ],
      "a commit that is not a hash" => [ { "commit" => "not-a-hash" }, /does not match/ ],
      "an id in the wrong format" => [ { "id" => "M99_01" }, /does not match/ ]
    }.each do |description, (override, message)|
      it "rejects #{description}" do
        violations = violations_for(pack_with(override))

        expect(violations.map(&:rule)).to include("SCHEMA")
        expect(violations.map(&:detail).join("\n")).to match(message)
      end
    end

    it "rejects an empty name" do
      violations = violations_for(pack_with("name" => ""))

      expect(violations.map(&:rule)).to include("SCHEMA")
    end

    it "rejects a blockedReason carrying a field the schema does not declare" do
      blocked = {
        "status" => "blocked",
        "blockedReason" => {
          "qualifier" => "BLOCKED_EXTERNAL_DEPENDENCY",
          "diagnosis" => "the registry is unreachable from this network, reproducibly",
          "escalated_to" => "someone"
        }
      }

      expect(violations_for(pack_with(blocked)).map(&:detail).join("\n"))
        .to match(/unknown property `escalated_to`/)
    end

    it "refuses to validate against a keyword it cannot apply" do
      expect { Opanel::Gates::JsonSchema.validate({ "allOf" => [] }, {}) }
        .to raise_error(Opanel::Gates::JsonSchema::UnsupportedKeyword, /allOf/)
    end
  end

  # AC2: one negative case per rule.
  describe "the rules" do
    it "rejects an invalid state" do
      expect(rules_for([ story("M99-01", status: "finished") ])).to include("STATE")
    end

    it "rejects a Story file that does not exist" do
      expect(rules_for([ story("M99-01") ], story_files: false)).to include("STORY_FILE")
    end

    it "rejects a dependsOn that names no Story of this Milestone" do
      expect(rules_for([ story("M99-01", dependsOn: [ "M99-99" ]) ])).to include("DEPENDENCY")
    end

    it "rejects a cycle" do
      stories = [
        story("M99-01", dependsOn: [ "M99-02" ]),
        story("M99-02", dependsOn: [ "M99-01" ])
      ]

      expect(rules_for(stories)).to include("NO_CYCLE")
    end

    it "rejects a Story marked done with no commit" do
      expect(rules_for([ story("M99-01", status: "done") ])).to include("DONE_HAS_COMMIT")
    end

    it "accepts a Story marked done with one" do
      expect(rules_for([ story("M99-01", status: "done", commit: "a1b2c3d") ])).to be_empty
    end

    it "says what to do, not only what is wrong" do
      with_pack([ story("M99-01", status: "done") ]) do |path, root|
        violation = described_class.validate(path, root).first

        expect(violation.remedy).to include("a claim, not a state")
      end
    end

    it "reports invalid JSON as itself rather than crashing" do
      Dir.mktmpdir do |root|
        directory = File.join(root, "docs/implementation/M99")
        FileUtils.mkdir_p(directory)
        File.write(File.join(directory, "tasks.json"), "{ not json")

        violations = described_class.validate(File.join(directory, "tasks.json"), root)

        expect(violations.map(&:rule)).to eq([ "PARSEABLE" ])
      end
    end
  end

  # AC8. A block that cannot be reproduced cannot be cleared, and a loop that
  # writes "blocked" with no diagnosis has simply stopped.
  describe "a blocked Story" do
    it "must carry a reason" do
      expect(rules_for([ story("M99-01", status: "blocked") ])).to include("BLOCKED_HAS_REASON")
    end

    it "must use one of the three qualifiers" do
      blocked = story("M99-01", status: "blocked", blockedReason: {
        "qualifier" => "BLOCKED_BECAUSE_HARD",
        "diagnosis" => "the thing did not work at all, repeatedly, for a while"
      })

      expect(rules_for([ blocked ])).to include("BLOCKED_HAS_REASON")
    end

    it "must diagnose it in more than a shrug" do
      blocked = story("M99-01", status: "blocked", blockedReason: {
        "qualifier" => "BLOCKED_EXTERNAL_DEPENDENCY", "diagnosis" => "broken"
      })

      expect(rules_for([ blocked ])).to include("BLOCKED_HAS_REASON")
    end

    it "is accepted when it says what happened and how to see it" do
      blocked = story("M99-01", status: "blocked", blockedReason: {
        "qualifier" => "BLOCKED_EXTERNAL_DEPENDENCY",
        "diagnosis" => "the registry is unreachable from this network; `docker pull busybox` hangs",
        "reproduce" => "docker pull busybox:latest"
      })

      expect(rules_for([ blocked ])).to be_empty
    end

    it "offers the three qualifiers and no others" do
      expect(described_class::QUALIFIERS).to contain_exactly(
        "BLOCKED_FOR_PRODUCT_DECISION",
        "BLOCKED_FOR_HUMAN_APPROVAL",
        "BLOCKED_EXTERNAL_DEPENDENCY"
      )
    end
  end

  # AC6. This plus `git log` is what makes a lost session recoverable.
  describe "the next Story" do
    def next_in(stories)
      with_pack(stories) do |_path, root|
        described_class.next_story("M99", root)
      end
    end

    it "respects dependsOn" do
      stories = [
        story("M99-01", status: "pending"),
        story("M99-02", status: "pending", dependsOn: [ "M99-01" ])
      ]

      expect(next_in(stories)["id"]).to eq("M99-01")
    end

    it "skips a Story whose dependency is not done" do
      stories = [
        story("M99-01", status: "blocked", blockedReason: {
          "qualifier" => "BLOCKED_FOR_HUMAN_APPROVAL",
          "diagnosis" => "needs a production decision before anything can be built on it"
        }),
        story("M99-02", status: "pending", dependsOn: [ "M99-01" ]),
        story("M99-03", status: "pending")
      ]

      expect(next_in(stories)["id"]).to eq("M99-03")
    end

    # Finishing beats starting: an abandoned in_progress Story is how a loop
    # ends up with six half-built things and no checkpoint.
    it "returns to work already underway before starting something new" do
      stories = [
        story("M99-01", status: "done", commit: "a1b2c3d"),
        story("M99-02", status: "pending"),
        story("M99-03", status: "in_progress")
      ]

      expect(next_in(stories)["id"]).to eq("M99-03")
    end

    it "returns nothing when every Story is done or blocked" do
      stories = [
        story("M99-01", status: "done", commit: "a1b2c3d"),
        story("M99-02", status: "blocked", blockedReason: {
          "qualifier" => "BLOCKED_EXTERNAL_DEPENDENCY",
          "diagnosis" => "the upstream API this Story integrates with is not released yet"
        })
      ]

      expect(next_in(stories)).to be_nil
    end

    it "answers for the real Milestone from the command line" do
      output, status = Open3.capture2e("bin/pack", "next", "M00", chdir: PACK_ROOT)

      expect(status).to be_success
      expect(output).to match(/M00-\d\d|no Story is eligible/)
    end
  end
end
