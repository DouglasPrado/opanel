require "rails_helper"

# AC5: the sanitisation is by **allowlist**, and a sensitive field planted in
# `before`/`after` is not persisted.
#
# The distinction the Story insists on is the one that decides what happens to a
# field nobody thought about. A blocklist records it — the failure is a leak. An
# allowlist omits it — the failure is a gap in the trail. These examples assert
# the second, including for keys this code has never seen.
RSpec.describe AuditSanitizer, type: :unit do
  describe "a field nobody allowed" do
    it "is dropped, not recorded" do
      result = described_class.call("Team", { "name" => "Ops", "internal_note" => "x" })

      expect(result).to eq({ "name" => "Ops" })
    end

    # The point of an allowlist: this is the field that does not exist yet.
    it "is dropped even when its name looks harmless" do
      result = described_class.call("Team", { "billing_reference" => "cus_123" })

      expect(result).to be_empty
    end

    it "is dropped for a resource type with no allowlist at all" do
      expect(described_class.call("SomethingNew", { "anything" => "value" })).to be_empty
      expect(described_class.new("SomethingNew").known?).to be(false)
    end
  end

  describe "a sensitive field" do
    # doc 04 §10.2: the *fact* of the change is auditable, the value never is.
    it "records that it changed and never what it changed to" do
      result = described_class.call("User", {
        "password_digest" => "$argon2id$v=19$m=65536,t=3,p=1$abc$def",
        "display_name" => "Ana"
      })

      expect(result["password_digest"]).to eq(described_class::MASK)
      expect(result["display_name"]).to eq("Ana")
      expect(result.values.join).not_to include("argon2id")
    end

    it "masks every name on the list" do
      planted = described_class::SENSITIVE.index_with { |name| "secret-value-for-#{name}" }

      result = described_class.call("User", planted)

      expect(result.values.uniq).to eq([ described_class::MASK ])
      expect(result.values.join).not_to include("secret-value-for")
    end

    it "masks it even for a resource type with no allowlist" do
      result = described_class.call("Unknown", { "token" => "raw-token-value" })

      expect(result).to eq({ "token" => described_class::MASK })
    end
  end

  describe "a nested value" do
    # An allowlist that only checks top-level keys is an allowlist bypassed one
    # level down: `{ name: { password: "x" } }` carries the password under an
    # approved key.
    #
    # These two examples previously asserted `be_a(String)` — which is **true**
    # when the value is `'{"password" => "hunter2"}'`, secret included. They named
    # the attack and could not detect it, and that is why the leak shipped green.
    # Every assertion here now names the planted value.
    it "does not carry a nested secret through under an allowed key" do
      result = described_class.call("Team", { "name" => { "password" => "PLANTED-hunter2" } })

      expect(result["name"]).to eq(described_class::OMITTED)
      expect(result.to_json).not_to include("PLANTED-hunter2")
      expect(result.to_json).not_to include("password")
    end

    it "does not let a disallowed key ride along inside an allowed one" do
      result = described_class.call("Team", { "status" => { "token_digest" => "PLANTED-abc" } })

      expect(result["status"]).to eq(described_class::OMITTED)
      expect(result.to_json).not_to include("PLANTED-abc")
    end

    it "drops an Array the same way, whatever it holds" do
      result = described_class.call("Team", { "name" => [ "ok", { "secret" => "PLANTED-x" } ] })

      expect(result["name"]).to eq(described_class::OMITTED)
      expect(result.to_json).not_to include("PLANTED-x")
    end

    it "drops an object, which `to_s` would have rendered" do
      leaky = Struct.new(:password).new("PLANTED-object")

      result = described_class.call("Team", { "name" => leaky })

      expect(result["name"]).to eq(described_class::OMITTED)
      expect(result.to_json).not_to include("PLANTED-object")
    end

    it "handles symbol keys, which reach it from attribute hashes" do
      result = described_class.call("Team", { name: { password: "PLANTED-sym" } })

      expect(result["name"]).to eq(described_class::OMITTED)
      expect(result.to_json).not_to include("PLANTED-sym")
    end
  end

  describe "what it does with ordinary values" do
    it "keeps scalars as they are" do
      result = described_class.call("TeamMember", { "role" => "OWNER", "status" => "ACTIVE" })

      expect(result).to eq({ "role" => "OWNER", "status" => "ACTIVE" })
    end

    it "renders times in a form a trail can be read in" do
      moment = Time.utc(2026, 9, 9, 12, 0, 0)

      result = described_class.call("TeamMember", { "joined_at" => moment })

      expect(result["joined_at"]).to eq(moment.iso8601)
    end

    it "returns an empty hash for nothing at all" do
      expect(described_class.call("Team", nil)).to eq({})
      expect(described_class.call("Team", {})).to eq({})
    end
  end

  # The list is the control. A model whose attributes are audited but which has no
  # entry records nothing, and that should be a decision rather than an oversight.
  describe "the allowlist itself" do
    it "covers every resource type the audit actions name" do
      expect(described_class::ALLOWED.keys)
        .to include("Team", "TeamMember", "User", "Session", "InstanceRole")
    end

    it "never allows a name that is also on the sensitive list" do
      overlap = described_class::ALLOWED.values.flatten & described_class::SENSITIVE

      expect(overlap).to be_empty
    end
  end
end
