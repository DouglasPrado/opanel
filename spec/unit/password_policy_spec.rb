require "rails_helper"

# The Story's failure table: a weak password is rejected "com política explícita",
# so the message has to state the rule the user broke — a generic refusal leaves
# them guessing — while never restating the whole policy as a checklist for an
# attacker.
RSpec.describe RegisterUser::PasswordPolicy, type: :unit do
  def violation(password, email: "person@example.test")
    described_class.violation(password: password, email: email)
  end

  it "accepts a long, unremarkable passphrase" do
    expect(violation("hunter2-hunter2-hunter2")).to be_nil
  end

  describe "length" do
    it "rejects anything shorter than the minimum and says the minimum" do
      expect(violation("short")).to include(described_class::MIN_LENGTH.to_s)
    end

    it "accepts exactly the minimum length" do
      expect(violation("a" * described_class::MIN_LENGTH)).to be_nil
    end

    it "rejects one character below the minimum" do
      expect(violation("a" * (described_class::MIN_LENGTH - 1))).to be_present
    end

    it "rejects a value above the maximum, which is a KDF denial-of-service bound" do
      # Argon2id costs 64 MiB per verification. An unbounded input is a way to
      # spend the server's memory from an unauthenticated route.
      expect(violation("a" * (described_class::MAX_LENGTH + 1))).to be_present
      expect(violation("a" * described_class::MAX_LENGTH)).to be_nil
    end

    it "bounds the maximum somewhere sane" do
      expect(described_class::MAX_LENGTH).to eq(256)
      expect(described_class::MIN_LENGTH).to eq(12)
    end
  end

  describe "the address" do
    it "rejects a password containing the address" do
      expect(violation("person@example.test-1", email: "person@example.test")).to be_present
    end

    it "rejects a password containing the local part of the address" do
      expect(violation("belladonna-flower", email: "belladonna@example.test")).to be_present
    end

    it "compares case-insensitively" do
      expect(violation("BELLADONNA-flower", email: "belladonna@example.test")).to be_present
    end

    it "does not reject a password that merely shares a few letters" do
      expect(violation("hunter2-hunter2-hunter2", email: "bella@example.test")).to be_nil
    end
  end

  describe "the common list" do
    it "rejects a password on the embedded common list" do
      expect(described_class::COMMON).not_to be_empty

      described_class::COMMON.each do |common|
        expect(violation(common.ljust(described_class::MIN_LENGTH, "1"))).to be_present,
          "expected #{common.inspect} to be refused"
      end
    end

    it "matches the list case-insensitively" do
      common = described_class::COMMON.first.ljust(described_class::MIN_LENGTH, "1")

      expect(violation(common.upcase)).to be_present
    end
  end

  describe "the message" do
    it "states the rule that was broken, so the user can comply" do
      expect(violation("short")).to match(/\d+ characters/)
    end

    it "does not enumerate the whole policy in one refusal" do
      expect(violation("short")).not_to include("common")
    end

    it "refuses a nil or blank value" do
      expect(violation(nil)).to be_present
      expect(violation("")).to be_present
    end
  end
end
