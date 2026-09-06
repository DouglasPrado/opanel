require "rails_helper"

RSpec.describe Opanel::Configuration, type: :unit do
  def validate(environment, source)
    described_class.validate(environment: environment, source: source)
  end

  describe "required keys" do
    it "accepts a complete production configuration" do
      problems = validate("production",
        "SECRET_KEY_BASE" => "a" * 64,
        "OPANEL_DATABASE_HOST" => "db.internal",
        "OPANEL_DATABASE_NAME" => "opanel_production",
        "OPANEL_DATABASE_USERNAME" => "opanel",
        "OPANEL_DATABASE_PASSWORD" => "irrelevant-for-this-test")

      expect(problems).to be_empty
    end

    it "reports a missing required key by name and by expected shape" do
      problems = validate("production", {})

      expect(problems).to include(a_string_matching(/SECRET_KEY_BASE is required in production/))
      expect(problems).to include(a_string_matching(/at least 32 characters/))
    end

    it "reports every missing key at once rather than one per boot attempt" do
      problems = validate("production", {})

      expect(problems.length).to be >= 5
      %w[SECRET_KEY_BASE OPANEL_DATABASE_HOST OPANEL_DATABASE_NAME
         OPANEL_DATABASE_USERNAME OPANEL_DATABASE_PASSWORD].each do |key|
        expect(problems.join("\n")).to include(key)
      end
    end

    it "requires nothing in development, where every default is safe" do
      expect(validate("development", {})).to be_empty
    end

    it "treats a blank value as missing" do
      problems = validate("production", "SECRET_KEY_BASE" => "   ")

      expect(problems).to include(a_string_matching(/SECRET_KEY_BASE is required/))
    end
  end

  describe "format validation" do
    it "rejects a malformed value and says what was expected" do
      problems = validate("development", "OPANEL_DATABASE_PORT" => "not-a-port")

      expect(problems).to include(a_string_matching(/OPANEL_DATABASE_PORT is set but has an invalid format/))
      expect(problems).to include(a_string_matching(/a non-negative integer/))
    end

    it "rejects a secret that is too short to be one" do
      problems = validate("production", "SECRET_KEY_BASE" => "short")

      expect(problems).to include(a_string_matching(/SECRET_KEY_BASE.*invalid format/))
    end

    it "rejects a supervisor mode outside the two that exist" do
      problems = validate("development", "OPANEL_JOB_SUPERVISOR_MODE" => "threads")

      expect(problems).to include(a_string_matching(/fork or async/))
    end

    it "accepts the modes that do exist" do
      %w[fork async].each do |mode|
        expect(validate("development", "OPANEL_JOB_SUPERVISOR_MODE" => mode)).to be_empty
      end
    end
  end

  describe "redaction" do
    it "never prints the value it received" do
      problems = validate("production",
        "SECRET_KEY_BASE" => "too-short-but-still-a-secret",
        "OPANEL_DATABASE_PASSWORD" => "hunter2")

      expect(problems.join("\n")).not_to include("too-short-but-still-a-secret")
      expect(problems.join("\n")).not_to include("hunter2")
    end

    it "still names the key, so the message is actionable" do
      problems = validate("production", "SECRET_KEY_BASE" => "short")

      expect(problems.join("\n")).to include("SECRET_KEY_BASE")
    end

    it "knows which keys carry credentials" do
      expect(described_class.sensitive_names).to include("SECRET_KEY_BASE", "OPANEL_DATABASE_PASSWORD")
      expect(described_class.sensitive_names).not_to include("OPANEL_DATABASE_PORT")
    end
  end

  describe "safe defaults" do
    it "gives a default only where the default cannot grant access" do
      described_class::KEYS.select { |key| key.default.present? }.each do |key|
        expect(key.sensitive?).to be(false),
          "#{key.name} is a credential and must not have a default — a default credential is an open door"
      end
    end

    it "defaults the database host to this machine" do
      expect(described_class.find("OPANEL_DATABASE_HOST").default).to eq("localhost")
    end
  end

  describe "the versioned example file" do
    let(:example) { Rails.root.join(".env.example").read }

    it "lists every declared key" do
      missing = described_class::KEYS.map(&:name).reject { |name| example.include?(name) }

      expect(missing).to be_empty, ".env.example is missing #{missing.inspect}"
    end

    it "declares no key the application does not read" do
      declared = example.scan(/^([A-Z][A-Z0-9_]+)=/).flatten
      unknown = declared - described_class::KEYS.map(&:name)

      expect(unknown).to be_empty,
        ".env.example declares #{unknown.inspect}, which nothing reads — a key nobody consumes is a lie"
    end

    it "carries no value for any sensitive key" do
      described_class.sensitive_names.each do |name|
        expect(example).to match(/^#{name}=\s*$/),
          "#{name} must be empty in the versioned example"
      end
    end

    it "says that configuration comes from the environment, not from a credentials file" do
      expect(example).to match(/no encrypted credentials file/)
    end
  end
end
