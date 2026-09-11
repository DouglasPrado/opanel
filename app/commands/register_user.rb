# Creates the account and signs the new user in (doc 10 UC-001).
#
# One transaction writes the user and the first session, because a registration
# that half succeeded — an account nobody is signed in to, or a session pointing
# at a row that was rolled back — is a state the product has no way to explain.
# The Argon2 hashing happens **before** the transaction opens: ~60 ms of CPU
# inside one holds a connection for no reason, and no network call happens inside
# it at all.
#
# Every refusal to create an account is the same refusal. Saying "that address is
# already registered" to an anonymous caller turns the sign-up form into an
# account-existence oracle, and saying it differently for a suspended or
# retained account turns it into a status oracle as well.
class RegisterUser
  EMAIL_UNAVAILABLE_MESSAGE =
    "That address cannot be used. If the account already exists, sign in or reset it instead."

  # The password rules, in one place, stated so the message can name the rule the
  # user broke. Kept here rather than in a class of its own: it has one caller
  # and one responsibility, and an abstraction with one caller is the
  # overengineering Annex I §2 rules out.
  module PasswordPolicy
    MIN_LENGTH = 12
    # An upper bound as well, and it is a denial-of-service control rather than a
    # style rule: every verification costs 64 MiB and ~60 ms, from a route that
    # needs no authentication.
    MAX_LENGTH = 256

    # Small and embedded on purpose. A full breach corpus is a dependency and a
    # data file; the point here is to refuse the handful of values that a
    # dictionary tries first.
    COMMON = %w[
      password passw0rd letmein qwerty iloveyou admin administrator welcome
      monkey dragon football baseball superman trustno1 sunshine princess
      changeme opanel
    ].freeze

    module_function

    # nil when the value is acceptable; otherwise the one rule it broke.
    def violation(password:, email: nil)
      candidate = password.to_s

      if candidate.length < MIN_LENGTH
        return "Use at least #{MIN_LENGTH} characters."
      end

      if candidate.length > MAX_LENGTH
        return "Use at most #{MAX_LENGTH} characters."
      end

      return "Do not use your email address." if contains_address?(candidate, email)

      folded = candidate.downcase
      return "That is too easy to guess. Choose something else." if COMMON.any? { |word| folded.include?(word) }

      nil
    end

    def contains_address?(candidate, email)
      address = email.to_s.strip.downcase
      return false if address.empty?

      folded = candidate.downcase
      return true if folded.include?(address)

      local = address.split("@").first.to_s
      local.length >= 4 && folded.include?(local)
    end
  end

  def self.call(email:, password:, display_name:, ip: nil, user_agent: nil)
    new(email: email, password: password, display_name: display_name,
      ip: ip, user_agent: user_agent).call
  end

  def initialize(email:, password:, display_name:, ip:, user_agent:)
    @email = User.normalize_email(email)
    @candidate = password
    @display_name = display_name.to_s.strip
    @ip = ip
    @user_agent = user_agent
  end

  def call
    invalid = shape_violation
    return rejected("VALIDATION_ERROR", invalid, reason: "policy") if invalid

    return rejected("RATE_LIMITED", RATE_LIMITED_MESSAGE, reason: "rate_limited") if throttled?

    AuthenticationAttempt.record(scope: "registration_ip", key: ip_key)

    return email_unavailable if User.exists?(email: email)

    # Outside the transaction, deliberately. See the class comment.
    digest = Opanel::PasswordHashing.create(candidate)
    token = Session.generate_token

    persist(digest, token)
  rescue ActiveRecord::RecordNotUnique
    # The check-then-insert window is real and the database is what closes it.
    # The answer has to be byte-identical to the pre-check's, or losing the race
    # becomes observable.
    email_unavailable
  end

  private

  RATE_LIMITED_MESSAGE = "Too many attempts from this network. Try again later."

  attr_reader :email, :candidate, :display_name, :ip, :user_agent

  def persist(digest, token)
    user = nil
    session = nil
    bootstrap = nil

    ApplicationRecord.transaction do
      user = User.create!(email: email, display_name: display_name,
        password_digest: digest, status: "ACTIVE")
      session = build_session(user, token)
      session.save!
      # In this transaction, not after it: AC1 of M01-03 requires User, Team,
      # OWNER membership and INSTANCE_ADMIN to be written together, and AC8
      # requires an interruption to leave nothing behind. The command decides for
      # itself whether this registration is the bootstrap — see its class comment
      # for why it does not ask first.
      bootstrap = BootstrapInstallation.call(user: user)

      # Inside the transaction (M01-05 AC11). A registration that committed with
      # no record of it, or a bootstrap that handed somebody the installation
      # untracked, are precisely the two this Milestone cannot afford to lose.
      AuditTrail.record(action: :user_registered, actor: user, resource: user,
        after: user.attributes, ip: ip, user_agent: user_agent)

      if bootstrap.success? && bootstrap.value[:bootstrapped]
        AuditTrail.record(action: :installation_bootstrapped, actor: user,
          resource: bootstrap.value[:team], team: bootstrap.value[:team],
          after: bootstrap.value[:team].attributes, ip: ip, user_agent: user_agent)
      end
    end

    Current.actor_id = user.external_id

    Rails.logger.info(event: "auth.register.succeeded", user_id: user.external_id,
      session_id: session.external_id)

    if bootstrap.success? && bootstrap.value[:bootstrapped]
      team = bootstrap.value[:team]
      # The Story asks for this event by name (Observability Requirements). The
      # AuditLog record of the same fact arrives with M01-05.
      Rails.logger.info(event: "installation.bootstrapped", user_id: user.external_id,
        team_id: team.external_id, roles: [ "OWNER", InstanceRole::ADMIN ])
    end

    Opanel::Result.success(user: user, session: session, session_token: token,
      bootstrapped: bootstrap.success? && bootstrap.value[:bootstrapped],
      team: bootstrap.success? ? bootstrap.value[:team] : nil)
  end

  def build_session(user, token)
    now = Time.current

    user.sessions.new(
      token_digest: Session.digest(token),
      expires_at: now + Session::ABSOLUTE_TTL,
      last_seen_at: now,
      mfa_level: "password",
      ip_address: ip,
      user_agent: user_agent&.to_s&.first(512)
    )
  end

  def shape_violation
    return "Enter an email address." if email.blank?
    return "Enter a valid email address." unless email.match?(User::EMAIL_FORMAT)
    return "That email address is too long." if email.length > User::EMAIL_MAX_LENGTH
    return "Enter a display name." if display_name.blank?
    return "That display name is too long." if display_name.length > User::DISPLAY_NAME_MAX_LENGTH

    RegisterUser::PasswordPolicy.violation(password: candidate, email: email)
  end

  def throttled?
    return false if ip.blank?

    AuthenticationAttempt.exceeded?(scope: "registration_ip", key: ip_key)
  end

  def ip_key
    ip.to_s.presence || "unknown"
  end

  def email_unavailable
    rejected("EMAIL_UNAVAILABLE", EMAIL_UNAVAILABLE_MESSAGE, reason: "email_unavailable")
  end

  # The reason is logged; the address never is. A log that records which address
  # was refused re-creates, for anyone who can read logs, the oracle the response
  # refuses to be.
  def rejected(code, message, reason:)
    Rails.logger.info(event: "auth.register.rejected", reason: reason)

    Opanel::Result.failure(code: code, message: message)
  end
end
