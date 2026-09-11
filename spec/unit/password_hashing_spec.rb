require "rails_helper"

# Annex B §13: a GPU-resistant hash, preferably Argon2id, with versioned
# parameters. Annex C §7.1: an updatable KDF, never reversible encryption. AC2.
RSpec.describe Opanel::PasswordHashing, type: :unit do
  # Obviously fake and allowlisted in config/security/gitleaks.toml.
  let(:secret) { "hunter2-hunter2-hunter2" }

  describe ".create" do
    it "returns a PHC string identifying Argon2id" do
      expect(described_class.create(secret)).to start_with("$argon2id$")
    end

    it "carries its own parameters, which is what makes them versioned" do
      # There is no `password_params_version` column and there must not be: the
      # cost is written into every digest, so raising it later cannot invalidate
      # an account created under the old one.
      digest = described_class.create(secret)

      expect(digest).to include("v=19")
      expect(digest).to include("m=#{2**described_class::PARAMETERS.fetch(:m_cost)}")
      expect(digest).to include("t=#{described_class::PARAMETERS.fetch(:t_cost)}")
      expect(digest).to include("p=#{described_class::PARAMETERS.fetch(:p_cost)}")
    end

    it "salts, so the same input twice produces two digests" do
      expect(described_class.create(secret)).not_to eq(described_class.create(secret))
    end

    it "never embeds the input it hashed" do
      expect(described_class.create(secret)).not_to include(secret)
    end

    it "uses at least the OWASP baseline cost" do
      expect(described_class::PARAMETERS.fetch(:m_cost)).to be >= 16
      expect(described_class::PARAMETERS.fetch(:t_cost)).to be >= 2
    end
  end

  describe ".verify" do
    it "accepts the value that produced the digest" do
      expect(described_class.verify(described_class.create(secret), secret)).to be(true)
    end

    it "rejects any other value" do
      expect(described_class.verify(described_class.create(secret), "#{secret}-x")).to be(false)
    end

    it "returns false for a malformed digest instead of raising" do
      # A corrupted or truncated column must fail the login, not take the
      # request down with an exception that names the column.
      expect(described_class.verify("not-a-digest", secret)).to be(false)
      expect(described_class.verify("$argon2id$broken", secret)).to be(false)
    end

    it "returns false for a nil or empty digest" do
      expect(described_class.verify(nil, secret)).to be(false)
      expect(described_class.verify("", secret)).to be(false)
    end

    it "returns false for a nil candidate" do
      expect(described_class.verify(described_class.create(secret), nil)).to be(false)
    end
  end

  describe ".needs_rehash?" do
    it "is false for a digest produced with the current parameters" do
      expect(described_class.needs_rehash?(described_class.create(secret))).to be(false)
    end

    it "is true for a digest produced with a weaker cost" do
      weaker = Argon2::Password.new(m_cost: 12, t_cost: 2, p_cost: 1).create(secret)

      expect(described_class.needs_rehash?(weaker)).to be(true)
    end

    it "is true for a digest that is not Argon2id at all" do
      expect(described_class.needs_rehash?("$2a$12$abcdefghijklmnopqrstuv")).to be(true)
    end

    it "is true for a malformed digest, so the next login repairs it" do
      expect(described_class.needs_rehash?("garbage")).to be(true)
    end
  end

  describe ".verify_dummy" do
    it "always answers false" do
      expect(described_class.verify_dummy(secret)).to be(false)
    end

    it "performs a real verification, so the unknown-address path costs the same" do
      # AC6 depends on this: an early return for an unknown address is a timing
      # oracle even when the response body is identical.
      expect(described_class).to receive(:verify).once.and_call_original

      described_class.verify_dummy(secret)
    end
  end

  it "offers no way back from a digest to the value" do
    # Annex C §7.1: never reversible encryption. There is no `decrypt`, and the
    # only route from a digest is a boolean.
    expect(described_class).not_to respond_to(:decrypt)
    expect(described_class).not_to respond_to(:reveal)
  end
end
