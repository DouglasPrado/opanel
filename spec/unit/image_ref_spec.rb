require "rails_helper"

# OCI image reference parsing and validation (doc 09 §5.3, AC7, Security Requirements).
RSpec.describe Opanel::ImageRef do
  describe "parsing a reference" do
    it "parses a simple image with default registry and tag" do
      ref = Opanel::ImageRef.new("nginx")
      parsed = ref.parse

      expect(parsed[:registry]).to eq("docker.io")
      expect(parsed[:repository]).to eq("nginx")
      expect(parsed[:tag]).to eq("latest")
      expect(parsed[:digest]).to be_nil
    end

    it "parses an image with an explicit tag" do
      ref = Opanel::ImageRef.new("nginx:1.24")
      parsed = ref.parse

      expect(parsed[:registry]).to eq("docker.io")
      expect(parsed[:repository]).to eq("nginx")
      expect(parsed[:tag]).to eq("1.24")
    end

    it "parses an image with a registry and tag" do
      ref = Opanel::ImageRef.new("gcr.io/my-project/my-service:v1.0")
      parsed = ref.parse

      expect(parsed[:registry]).to eq("gcr.io")
      expect(parsed[:repository]).to eq("my-project/my-service")
      expect(parsed[:tag]).to eq("v1.0")
    end

    it "parses an image with a digest" do
      digest = "sha256:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234"
      ref = Opanel::ImageRef.new("nginx@#{digest}")
      parsed = ref.parse

      expect(parsed[:registry]).to eq("docker.io")
      expect(parsed[:repository]).to eq("nginx")
      expect(parsed[:digest]).to eq(digest)
    end

    it "parses an image with registry, tag, and digest" do
      digest = "sha256:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234"
      ref = Opanel::ImageRef.new("docker.io/nginx:1.24@#{digest}")
      parsed = ref.parse

      expect(parsed[:registry]).to eq("docker.io")
      expect(parsed[:repository]).to eq("nginx")
      expect(parsed[:tag]).to eq("1.24")
      expect(parsed[:digest]).to eq(digest)
    end

    it "detects mutable tags (not digests)" do
      # Mutable: tag-based references without a digest.
      expect(Opanel::ImageRef.new("nginx:latest").mutable_tag?).to be true
      expect(Opanel::ImageRef.new("nginx").mutable_tag?).to be true
      expect(Opanel::ImageRef.new("nginx:1.0").mutable_tag?).to be true
    end

    it "detects immutable digests" do
      digest = "sha256:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234"
      expect(Opanel::ImageRef.new("nginx@#{digest}").mutable_tag?).to be false
    end
  end

  describe "validation" do
    it "rejects an empty reference" do
      expect {
        Opanel::ImageRef.new("").parse
      }.to raise_error(Opanel::ImageRef::InvalidReference)
    end

    it "rejects a reference with only whitespace" do
      expect {
        Opanel::ImageRef.new("   ").parse
      }.to raise_error(Opanel::ImageRef::InvalidReference)
    end

    it "rejects an invalid digest" do
      expect {
        Opanel::ImageRef.new("nginx@sha256:notahash").parse
      }.to raise_error(Opanel::ImageRef::InvalidReference)
    end

    it "rejects an invalid tag" do
      expect {
        Opanel::ImageRef.new("nginx:inv@lid").parse
      }.to raise_error(Opanel::ImageRef::InvalidReference)
    end

    it "accepts references with hyphens, dots, and underscores in the repository" do
      expect {
        Opanel::ImageRef.new("my-registry.com/my_project/my-service:v1").parse
      }.not_to raise_error
    end
  end

  describe "security: escaping and SSRF" do
    it "parses legitimate multi-segment repositories" do
      # Legitimate: docker.io/library/nginx.
      ref = Opanel::ImageRef.new("docker.io/library/nginx")
      expect(ref.parse[:repository]).to eq("library/nginx")
    end

    it "defaults to docker.io for unqualified references" do
      # Without an explicit registry, the image is docker.io.
      ref = Opanel::ImageRef.new("nginx:latest")
      expect(ref.parse[:registry]).to eq("docker.io")
    end
  end
end
