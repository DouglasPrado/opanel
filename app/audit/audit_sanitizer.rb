# What may enter an audit record's `before`/`after`, decided by allowlist.
#
# ## Why allowlist and not blocklist, in one sentence
#
# A blocklist is wrong by default: a field added next year is recorded until
# somebody remembers to forbid it, and the failure is a leak. An allowlist is
# empty by default: the same field is omitted until somebody decides to record it,
# and the failure is a gap in the trail. The Story's Security Requirements say it
# outright — *"um campo novo não auditado por engano é omitido, não vazado"*.
#
# `Opanel::Redaction` already masks sensitive keys at the log sink and is not
# duplicated here; it answers a different question. Redaction asks *"does this
# value look sensitive?"*, which is a guess made after the fact. This asks *"was
# this field approved for the trail?"*, which is a decision made in advance. The
# audit record is the one place where a guess is not good enough, so both exist:
# the allowlist decides what is written, and redaction stays as the net under the
# ordinary log.
#
# ## Sensitive fields that changed
#
# A change to a secret must be *auditable* without being *readable*. A field in
# `SENSITIVE` is recorded as the fact that it changed — never the value, on either
# side — which is what doc 04 §10.2 requires and what makes the trail useful for
# "who rotated this and when" without making it a second copy of the vault.
class AuditSanitizer
  MASK = "[CHANGED]"

  # A value whose shape the allowlist cannot vouch for: a Hash, an Array, an
  # object. Recorded as having been present, never as its content.
  OMITTED = "[OMITTED]"

  # Per resource type, the fields whose values may be recorded. Adding a field
  # here is a deliberate line in a diff somebody reviews — which is the point.
  ALLOWED = {
    # The payload of an authorization denial, keyed by its own name rather than by
    # a resource type: the record is *about* a Team or a TeamMember, but what it
    # carries is the refusal, not the resource. The vocabulary is
    # `ApplicationPolicy::REASONS`, never user input — and it still goes through
    # the allowlist, so there is one path into `after` rather than two.
    "AuthorizationDenial" => %w[reason].freeze,
    "Team" => %w[name slug status owner_user_id deleted_at].freeze,
    # `description` is here because a rename or an edit of it is exactly what the
    # trail of `M01-07` has to answer for, and a `before`/`after` without the field
    # that changed records that something happened and not what. It is user prose
    # about the user's own Project — the same exposure `Team.name` already carries —
    # and the `SENSITIVE` list above still applies to every key by name.
    "Project" => %w[name slug description status team_id default_environment_id deleted_at].freeze,
    "TeamMember" => %w[role status joined_at].freeze,
    "User" => %w[display_name status email_verified_at].freeze,
    "Session" => %w[expires_at revoked_at last_seen_at mfa_level].freeze,
    "InstanceRole" => %w[role revoked_at granted_by_bootstrap].freeze
  }.freeze

  # See the comment inside ALLOWED.
  DENIAL_TYPE = "AuthorizationDenial"

  # Fields whose *change* is recorded and whose value never is. They are listed
  # rather than derived from a pattern, so a rename cannot quietly turn one into
  # an ordinary field.
  SENSITIVE = [
    %w[password password_digest token token_digest secret secret_value], # REDACTED: named here to be refused
    %w[private_key recovery_key api_key access_token refresh_token client_secret] # REDACTED: named here to be refused
  ].flatten.freeze

  def self.call(resource_type, attributes)
    new(resource_type).call(attributes)
  end

  def initialize(resource_type)
    @resource_type = resource_type.to_s
  end

  # Returns a Hash safe to persist. Anything not explicitly allowed is dropped,
  # including keys this class has never heard of.
  def call(attributes)
    return {} if attributes.blank?

    attributes.each_with_object({}) do |(key, value), result|
      name = key.to_s

      if SENSITIVE.include?(name)
        result[name] = MASK
      elsif allowed.include?(name)
        result[name] = scalar(value)
      end
    end
  end

  # Whether this resource type has any allowlist at all. A type nobody has
  # thought about records no values — and `AuditTrail` says so out loud rather
  # than silently writing `{}`.
  def known? = ALLOWED.key?(@resource_type)

  private

  def allowed = ALLOWED.fetch(@resource_type, [])

  # Only scalars reach the record, and anything else is **dropped** rather than
  # stringified.
  #
  # An earlier version ended in `value.to_s`, which was worse than useless: a Hash
  # under an allowed key came out as `'{"password" => "hunter2"}'` — the secret
  # preserved verbatim inside a String, past an allowlist that had approved only
  # the outer key. Stringifying converts the *type* and keeps the *content*, so it
  # defeats exactly the check it appears to perform. The review caught it with a
  # planted value; the spec that named this attack asserted only `be_a(String)`,
  # which is true with the secret inside.
  #
  # `OMITTED` says a value was present and was not recorded, which is what a
  # reader of the trail needs. Dropping the key silently would make "the field was
  # empty" and "the field carried something we would not store" the same.
  def scalar(value)
    case value
    when nil, true, false, Numeric, String then value
    when Symbol then value.to_s
    when Time, DateTime, Date, ActiveSupport::TimeWithZone then value.iso8601
    else OMITTED
    end
  end
end
