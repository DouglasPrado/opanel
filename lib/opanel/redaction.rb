# frozen_string_literal: true

module Opanel
  # The last barrier before a value reaches a log, an error message or a health
  # response.
  #
  # Redaction happens **at the origin and at the sink** (Annex C §17.1). Code that
  # knows a value is a secret must not log it; this exists because that discipline
  # fails eventually — a driver interpolates a connection string into an
  # exception, a middleware dumps a header, a payload is inspected during
  # debugging. The sink cannot know what the value means, so it matches shape.
  #
  # Two kinds of rule:
  #
  #   * **Keys** — a field named `password`, `token`, `authorization`, `cookie`
  #     has its value replaced regardless of what the value looks like.
  #   * **Patterns** — a credential shape anywhere in free text: a connection URL
  #     carrying a password, a bearer token, a private key block.
  #
  # It errs toward masking. A masked value that was not a secret costs one
  # debugging round trip; the reverse is a leak that cannot be recalled.
  module Redaction
    MASK = "[REDACTED]"

    # A field whose *name* means its value is sensitive, whatever the value is.
    SENSITIVE_KEY = /\A(
      .*password.* | .*passwd.* | .*secret.* | .*token.* | .*api[_-]?key.* |
      authorization | .*credential.* | cookie | set-cookie | .*private[_-]?key.* |
      .*passphrase.* | .*recovery[_-]?key.* | .*session[_-]?id.* | .*signature.*
    )\z/xi

    # A credential shape in free text.
    PATTERNS = [
      # Authorization: Bearer <token>
      [ /\b(Bearer|Basic|Token)\s+[A-Za-z0-9._\-\/+=]{8,}/i, '\1 ' + MASK ],
      # password=..., password: ...
      [ /((?:password|passwd|pwd|secret|passphrase|token|api[_-]?key)"?\s*[:=]\s*"?)([^"\s,;}]{3,})/i,
        '\1' + MASK ],
      # scheme://user:password@host
      [ %r{(\b[a-z][a-z0-9+.\-]*://[^\s:/@"]+:)([^\s@"]{1,})(@)}i, '\1' + MASK + '\3' ],
      # A private key block, however long.
      [ /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m, MASK ],
      [ /-----BEGIN [A-Z ]*PRIVATE KEY-----/, MASK ],
      # Cookie header contents.
      [ /((?:set-)?cookie"?\s*[:=]\s*"?)([^"\r\n;]{4,})/i, '\1' + MASK ]
    ].freeze

    module_function

    # Masks a String, or every sensitive value inside a Hash or Array. Anything
    # else is returned untouched.
    def apply(value, key: nil)
      case value
      when String then sensitive_key?(key) ? MASK : scrub(value)
      when Symbol, Numeric, TrueClass, FalseClass, NilClass then sensitive_key?(key) ? MASK : value
      when Hash then value.to_h { |nested_key, nested| [ nested_key, apply(nested, key: nested_key) ] }
      when Array then value.map { |element| apply(element, key: key) }
      else
        sensitive_key?(key) ? MASK : apply(value.to_s, key: key)
      end
    end

    def sensitive_key?(key)
      return false if key.nil?

      key.to_s.match?(SENSITIVE_KEY)
    end

    def scrub(text)
      PATTERNS.reduce(text) { |result, (pattern, replacement)| result.gsub(pattern, replacement) }
    end
  end
end
