# Validation and parsing of OCI image references (doc 09 §5.3, Security Requirements).
#
# An image reference consists of:
#   - Optional registry (default: docker.io for brevity, or explicit)
#   - Repository
#   - Optional tag (default: "latest")
#   - Optional digest (sha256:...)
#
# ## Validation scope for M01-12
#
# This validator performs syntax validation only:
# - Parses the reference into registry, repository, tag and optional digest
# - Rejects references with invalid syntax (bad characters, format violations)
# - Detects whether a digest is present (immutable) or only a tag (mutable)
# - Does not fetch, resolve or validate against any registry
#
# Mutable tag resolution (converting tag to immutable digest) happens in the
# reconciler (M01-18), not in M01-12. If the user supplies an explicit digest,
# it is captured by CreateService#parse and stored in image_digest per AC7.
#
module Opanel
  class ImageRef
    # OCI repository name format: alphanumeric, hyphens, underscores, dots, slashes.
    # Simplified validation: no directory traversal, no special schemes.
    REPOSITORY_FORMAT = /\A[a-z0-9._\/-]+\z/i
    TAG_FORMAT = /\A[a-zA-Z0-9._:-]+\z/
    DIGEST_FORMAT = /\Asha256:[a-f0-9]{64}\z/i

    class InvalidReference < StandardError; end
    class MutableTagError < StandardError; end

    def initialize(reference)
      @reference = reference.to_s.strip
    end

    # Parses the reference and returns a normalized structure.
    # Raises InvalidReference if the format is invalid.
    def parse
      raise InvalidReference, "reference cannot be empty" if @reference.blank?

      # Extract registry, repository, tag, digest.
      # Format: [registry/]repository[:tag][@digest]
      registry, repo_part = extract_registry_and_repo

      repository, tag, digest = extract_parts(repo_part)

      {
        registry: registry,
        repository: repository,
        tag: tag,
        digest: digest,
        reference: @reference
      }
    end

    # Whether the reference contains a digest (immutable) rather than just a tag.
    def has_digest?
      @reference.include?("@sha256:")
    end

    # Whether the reference has a mutable tag (i.e., not a digest).
    # "latest" and omitted tag are both mutable.
    def mutable_tag?
      !has_digest?
    end

    private

    def extract_registry_and_repo
      # If the first segment contains a dot or colon, treat it as registry.
      # Otherwise, default to docker.io.
      if @reference.include?("/")
        first_slash = @reference.index("/")
        first_segment = @reference[0...first_slash]

        if first_segment.include?(".") || first_segment.include?(":")
          registry = first_segment
          repo_part = @reference[first_slash + 1..]
          [ registry, repo_part ]
        else
          [ "docker.io", @reference ]
        end
      else
        [ "docker.io", @reference ]
      end
    end

    def extract_parts(repo_part)
      # Split on @ to get digest first.
      if repo_part.include?("@")
        repo_and_tag, digest = repo_part.split("@", 2)
        raise InvalidReference, "invalid digest format" unless digest.match?(DIGEST_FORMAT)
      else
        repo_and_tag = repo_part
        digest = nil
      end

      # Split on : to get tag. Use the last : in case there are multiple colons
      # (e.g., in the registry:port).
      last_colon = repo_and_tag.rindex(":")
      if last_colon
        repository = repo_and_tag[0...last_colon]
        tag = repo_and_tag[(last_colon + 1)..]
        raise InvalidReference, "invalid tag format" unless tag.match?(TAG_FORMAT)
      else
        repository = repo_and_tag
        tag = "latest"
      end

      raise InvalidReference, "invalid repository format" unless repository.match?(REPOSITORY_FORMAT)

      [ repository, tag, digest ]
    end
  end
end
