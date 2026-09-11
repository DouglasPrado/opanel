# Who is making this request, and may they.
#
# **Deny by default.** The `before_action` is installed by including this
# concern, so every controller written after this Story is authenticated unless
# it declares otherwise with `allow_unauthenticated_access`. The other ordering —
# an opt-in `require_authentication` — fails open on the day somebody forgets,
# and that is the only day it matters (Annex I §2, "Secure by default").
#
# **Nothing about the session is cached.** The cookie carries a random token and
# nothing else: no user id, no expiry, no role. Every request resolves it against
# the row, so a session revoked on another device stops working on the very next
# request rather than on the next navigation (AC4). That is one indexed read on
# a unique index, which is the price of revocation being real.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :opanel_session

  included do
    before_action :resume_session
    before_action :require_authentication

    helper_method :current_user, :current_session, :signed_in?
  end

  class_methods do
    # The declaration a public controller makes. Named as an allowance rather
    # than a skip so that reading the controller tells you it is public.
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def current_session
    @current_session
  end

  def current_user
    current_session&.user
  end

  def signed_in?
    current_session.present?
  end

  # Runs on every request, including the public ones, so a public page can still
  # know who is reading it.
  def resume_session
    token = cookies.signed[COOKIE]
    return if token.blank?

    session_record = Session.active.find_by(token_digest: Session.digest(token))

    if session_record.nil?
      # Expired, revoked, or a value that matches no row. In all three cases the
      # browser should stop sending it.
      clear_session_cookie
      return
    end

    @current_session = session_record
    Current.actor_id = session_record.user.external_id
    session_record.touch_last_seen! if session_record.stale_last_seen?
  end

  def require_authentication
    return if signed_in?

    remember_destination
    redirect_to sign_in_path
  end

  # Only a path from this application, and only for a GET that a browser would
  # navigate to. A destination taken from a parameter is an open redirect, and a
  # destination taken from a POST would replay a mutation after sign-in.
  def remember_destination
    return unless request.get?

    destination = request.fullpath
    return unless destination.start_with?("/") && !destination.start_with?("//")

    session[:return_to] = destination
  end

  def destination_after_authentication
    candidate = session.delete(:return_to)

    return panel_home if candidate.blank?
    return panel_home unless candidate.start_with?("/") && !candidate.start_with?("//")

    candidate
  end

  # Where somebody lands when they have not asked for anywhere in particular: the
  # panel of a Team they can act in (M01-06 AC1). Until that Story the answer was
  # `root_path`, which is the M00 example page — signing in and arriving at a demo
  # is not "the user sees the app shell".
  #
  # No Team is a real state: an account created before the installation was
  # bootstrapped has none. It gets the Team list, which is where it can make one.
  def panel_home
    team = current_user && TenantScope.for(current_user, Team).relation.order(:name).first

    team ? "/t/#{team.slug}/projects" : teams_path
  end

  def start_session(session_record, token)
    @current_session = session_record

    cookies.signed[COOKIE] = {
      value: token,
      httponly: true,
      same_site: :lax,
      # On in test as well as production, so what the request spec reads is the
      # real attribute rather than a branch that only exists somewhere else.
      # Development is the exception because it is served over plain HTTP.
      # Secure whenever the request is actually over TLS, rather than keyed on the
      # environment name.
      #
      # `!Rails.env.development?` looked equivalent and was not: the E2E server
      # runs the **test** environment over plain HTTP, so the browser silently
      # discarded every session cookie and no authenticated journey could ever
      # sign in. The failure had no error — the redirect simply landed back on
      # /sign_in.
      #
      # This is not a relaxation. Behind TLS — which production enforces with
      # `force_ssl`, redirecting HTTP before a cookie is ever set — `request.ssl?`
      # is true and the flag is set. The request specs drive `https!` and still
      # assert the real attribute.
      secure: request.ssl?,
      path: "/",
      expires: session_record.expires_at
    }
  end

  def clear_session_cookie
    @current_session = nil
    cookies.delete(COOKIE, path: "/")
  end
end
