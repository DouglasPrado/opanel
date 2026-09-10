require "rails_helper"

# The two patterns M01-09 adds to `Opanel::Redaction`, and proof that adding
# them left the existing ones alone. Planted values, in the shape the real ones
# have — the redaction matches by shape, so shape is the whole requirement.
RSpec.describe Opanel::Redaction, type: :unit do
  MASK = Opanel::Redaction::MASK

  describe "a registry credential on the wire (X-Registry-Auth)" do
    it "is masked when it appears as a header" do
      text = "X-Registry-Auth: not-a-real-registry-auth-value-x1 rest"

      expect(described_class.apply(text)).to eq("X-Registry-Auth: #{MASK} rest")
    end

    it "is masked regardless of case and separator" do
      redacted = described_class.apply('"x-registry-auth"="not-a-real-registry-auth-x2"')

      expect(redacted).not_to include("not-a-real-registry")
    end
  end

  describe "a Swarm join token" do
    it "is masked wherever it appears" do
      text = "run: docker swarm join --token SWMTKN-1-example-not-a-real-token-x1 10.0.0.5:2377"

      redacted = described_class.apply(text)

      expect(redacted).not_to include("SWMTKN")
      expect(redacted).to include("10.0.0.5:2377")
    end
  end

  # The control: the patterns that were there before still fire, and ordinary
  # text is untouched. A redaction that ate everything would pass every "does
  # not include" assertion above.
  describe "what did not change" do
    it "still masks a bearer token" do
      expect(described_class.apply("Authorization: Bearer not-a-real-bearer-token-x1"))
        .to eq("Authorization: Bearer #{MASK}")
    end

    it "still masks a credential inside a URL" do
      expect(described_class.apply("https://user:hunter2@registry.example")).to eq("https://user:#{MASK}@registry.example")
    end

    it "leaves an ordinary sentence alone" do
      text = "service web updated to version 12 on node-1"

      expect(described_class.apply(text)).to eq(text)
    end

    it "still classifies sensitive keys" do
      expect(described_class.sensitive_key?("registry_password")).to be(true)
      expect(described_class.sensitive_key?("image")).to be(false)
    end
  end
end
