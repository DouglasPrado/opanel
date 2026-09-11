# Sign in, sign out, and the account's own session list (doc 04 §8.2).
#
# Everything is served by Inertia. No REST endpoint exists to feed these pages
# and none should: the public API exists for MCP, the CLI and automation, and it
# will reuse these same Commands rather than duplicating their rules.
#
# `new` and `create` are the only public actions; `index` and `destroy` inherit
# the deny-by-default of `Authentication`.
class SessionsController < ApplicationController
  include ErrorEnvelope

  allow_unauthenticated_access only: %i[new create]

  SIGN_IN_PAGE = "Auth/SignIn"
  SESSIONS_PAGE = "Account/Sessions"

  def new
    return redirect_to root_path if signed_in?

    render inertia: SIGN_IN_PAGE
  end

  def create
    result = AuthenticateUser.call(
      email: submitted[:email],
      password: submitted[:password],
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.failure?
      return render inertia: SIGN_IN_PAGE,
        props: { error: error_envelope(result) },
        status: error_status(result)
    end

    destination = destination_after_authentication
    start_session(result.value.fetch(:session), result.value.fetch(:session_token))
    redirect_to destination
  end

  def index
    render inertia: SESSIONS_PAGE, props: sessions_props
  end

  # Two routes reach this action: `DELETE /sign_out`, which ends the session
  # making the request, and `DELETE /settings/sessions/:id`, which ends a named
  # one. They are the same operation — a revocation the server performs — and
  # splitting them into two controllers would duplicate the cookie handling that
  # both need when the named session turns out to be this one.
  def destroy
    return sign_out_current if params[:id].blank?

    revoke_named
  end

  private

  def sign_out_current
    session_record = current_session
    session_record&.revoke!

    if session_record
      Rails.logger.info(event: "auth.session.revoked", session_id: session_record.external_id,
        revoked_by: "logout")
    end

    clear_session_cookie
    redirect_to sign_in_path
  end

  def revoke_named
    result = RevokeSession.call(actor: current_user, session_id: params[:id])

    if result.failure?
      return render inertia: SESSIONS_PAGE,
        props: sessions_props.merge(error: error_envelope(result)),
        status: error_status(result)
    end

    # Revoking the session you are using is a sign-out. Leaving the cookie in
    # place would leave the browser presenting a credential the server has
    # already withdrawn.
    return sign_out_after_self_revocation if result.value.id == current_session&.id

    redirect_to account_sessions_path
  end

  def sign_out_after_self_revocation
    clear_session_cookie
    redirect_to sign_in_path
  end

  def sessions_props
    entries = UserSessions.call(user: current_user, current_session_id: current_session&.id)

    { sessions: entries.map { |entry| session_prop(entry) } }
  end

  # The props the page reads, named the way the React tree names things. Written
  # out field by field rather than dumped from the record: what leaves the server
  # is a decision, and a list nobody wrote is a list nobody reviewed.
  def session_prop(entry)
    {
      id: entry.id,
      current: entry.current,
      active: entry.active,
      ipAddress: entry.ip_address,
      userAgent: entry.user_agent,
      lastSeenAt: entry.last_seen_at&.iso8601,
      createdAt: entry.created_at&.iso8601,
      expiresAt: entry.expires_at&.iso8601,
      revokedAt: entry.revoked_at&.iso8601
    }
  end

  def submitted
    params.permit(:email, :password)
  end
end
