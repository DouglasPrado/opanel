# Verifies a credential and opens a session (doc 04 §8, Annex C §7.1).
#
# **Every failure is the same failure.** An unknown address, a wrong password, a
# suspended account and one pending deletion all return one code and one message,
# because any difference between them answers "does this account exist" — the
# question AC6 says the response must not answer. The unknown-address branch runs
# `verify_dummy` for the same reason: identical bodies with a 60 ms difference in
# arrival time are still an oracle.
#
# The throttle counts failures for unknown and known addresses alike. Counting
# only real accounts would move that oracle into the rate limiter.
class AuthenticateUser
  INVALID_CREDENTIALS_MESSAGE = "Incorrect email or password."
  RATE_LIMITED_MESSAGE = "Too many attempts. Try again in a few minutes."

  def self.call(email:, password:, ip: nil, user_agent: nil)
    new(email: email, password: password, ip: ip, user_agent: user_agent).call
  end

  def initialize(email:, password:, ip:, user_agent:)
    @email = User.normalize_email(email)
    @candidate = password
    @ip = ip
    @user_agent = user_agent
  end

  def call
    return rate_limited if throttled?

    user = User.find_by(email: email) if email.present?

    return refused(user_present: false) if user.nil?
    return refused(user_present: true) unless verified?(user)
    return refused(user_present: true) unless user.authenticatable?

    granted(user)
  end

  private

  attr_reader :email, :candidate, :ip, :user_agent

  def verified?(user)
    Opanel::PasswordHashing.verify(user.password_digest, candidate)
  end

  def granted(user)
    token = Session.generate_token
    session = nil

    ApplicationRecord.transaction do
      session = build_session(user, token)
      session.save!
      AuthenticationAttempt.clear(scope: "login_email", key: email)
    end

    # After the transaction, never inside it: raising the cost must not lengthen
    # the time a row is locked, and a failure to re-hash must not undo a
    # successful login.
    upgrade_digest(user)

    Current.actor_id = user.external_id
    Rails.logger.info(event: "auth.login.succeeded", user_id: user.external_id,
      session_id: session.external_id, mfa_level: session.mfa_level)

    Opanel::Result.success(user: user, session: session, session_token: token)
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

  # Rehash on login is how "parâmetros atualizáveis" (Annex C §7.1) actually
  # happens: the digest carries the cost it was made with, so raising
  # `PARAMETERS` upgrades accounts as their owners sign in, and invalidates none.
  #
  # Explicit here rather than in an Active Record callback: it is a deliberate
  # step in an authentication flow, and a callback would hide it from anyone
  # reading this command to find out what a login does.
  def upgrade_digest(user)
    return unless Opanel::PasswordHashing.needs_rehash?(user.password_digest)

    user.update_column(:password_digest, Opanel::PasswordHashing.create(candidate))
  end

  # `user_present` never reaches the caller or the log. It exists so the two
  # branches can differ in *cost* — the dummy verification — while being
  # identical in every observable way.
  def refused(user_present:)
    Opanel::PasswordHashing.verify_dummy(candidate) unless user_present

    record_failure

    Rails.logger.info(event: "auth.login.failed", reason: "invalid_credentials", ip: ip)

    Opanel::Result.failure(code: "INVALID_CREDENTIALS", message: INVALID_CREDENTIALS_MESSAGE)
  end

  def record_failure
    AuthenticationAttempt.record(scope: "login_email", key: email.to_s) if email.present?
    AuthenticationAttempt.record(scope: "login_ip", key: ip.to_s) if ip.present?
    AuthenticationAttempt.sweep
  end

  def throttled?
    throttled_scope.present?
  end

  # Both scopes are evaluated and either one blocks. The address limit stops one
  # account being ground down; the IP limit stops the same client spraying a
  # different address every time, which never trips the first.
  def throttled_scope
    return @throttled_scope if defined?(@throttled_scope)

    @throttled_scope =
      if email.present? && AuthenticationAttempt.exceeded?(scope: "login_email", key: email)
        "login_email"
      elsif ip.present? && AuthenticationAttempt.exceeded?(scope: "login_ip", key: ip.to_s)
        "login_ip"
      end
  end

  def rate_limited
    Rails.logger.warn(event: "auth.login.rate_limited", scope: throttled_scope, ip: ip)

    Opanel::Result.failure(code: "RATE_LIMITED", message: RATE_LIMITED_MESSAGE)
  end
end
