class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # An Inertia visit is still a form submission as far as the browser is
  # concerned, so CSRF protection applies to it exactly as it would to any other
  # non-GET request. Raising, rather than resetting the session, makes a rejected
  # request visible instead of silently anonymous.
  protect_from_forgery with: :exception

  # Deny by default (M01-01). Included after CSRF protection so an unauthenticated
  # forged request is refused as forgery rather than as a redirect to sign in, and
  # so every controller written from here on is authenticated unless it declares
  # `allow_unauthenticated_access`.
  include Authentication

  # A Policy refusing an action is an answer, not a crash.
  #
  # `M01-07` is the first Story whose Commands authorize, and until it there was
  # nothing to raise this — a role refusal came back as a 500, which tells the
  # user nothing and tells a log reader that the server is broken when it is
  # working exactly as designed.
  #
  # **403, and only for an actor who may already see the resource.** A caller
  # from another Team never reaches here: the tenancy boundary answers 404 first,
  # and it has to, because a 403 across Teams confirms the resource exists
  # (Annex C §7.3). What this renders is the other case — a member of the right
  # Team whose role does not carry the action.
  #
  # The body carries no exception class, no backtrace and no path. The classified
  # reason stays in the audit record and the application log, where
  # `Opanel::Authorization` already wrote it.
  rescue_from Opanel::Authorization::Denied, with: :render_forbidden

  # Props shared with every page.
  #
  # Nothing sensitive goes here. Shared props are serialized into the HTML of
  # every response: a token placed here is a token published to the browser.
  # `spec/security/inertia_shared_props_spec.rb` asserts it, and AF-06 (M00-13)
  # will enforce it beyond this file.
  inertia_share do
    {
      requestId: request.request_id,
      flash: {
        notice: flash.notice,
        alert: flash.alert
      }
    }.merge(panel_props)
  end

  private

  # What the app shell needs on every authenticated page: who is signed in, and
  # which Teams they may act in. Absent — not null — when nobody is signed in, so
  # sign-in and sign-up publish nothing about anybody.
  #
  # Deliberately narrow. Shared props are serialized into the HTML of every
  # response, so this carries an id, a display name and an address, and no role
  # list, session id or token. `spec/security/inertia_shared_props_spec.rb`
  # asserts it; AF-06 covers the sinks.
  def panel_props
    user = respond_to?(:current_user, true) ? current_user : nil
    return {} if user.nil?

    teams = TeamsForUser.call(user: user)

    {
      currentUser: { id: user.external_id, name: user.display_name, email: user.email },
      teams: teams.map { |entry| shared_team_prop(entry) },
      currentTeam: shared_current_team_prop(teams)
    }
  end

  # Named `shared_` on purpose. `TeamsController` has its own `team_prop` for a
  # `Team`, and an unprefixed name here would be overridden by it — the subclass
  # method would then receive a `TeamsForUser::Entry` and fail on a `Team` method.
  # That is not hypothetical: it is what happened, and it broke five specs in
  # three files at once.
  def shared_team_prop(entry)
    { id: entry.id, name: entry.name, slug: entry.slug, role: entry.role }
  end

  # The same page, the same three props and the same fixed sentence
  # `ErrorsController` renders for a 403. Reused rather than given a shape of its
  # own: a second contract for the same status is a second thing to keep true,
  # and the request id the operator needs is already a shared prop.
  #
  # `decision.reason` is deliberately not shown. It distinguishes "your role does
  # not permit this" from "you have no membership", and telling an actor which
  # one it is turns a refusal into an oracle about the Team.
  def render_forbidden(_error)
    render inertia: "Error",
      props: {
        status: 403,
        title: Rack::Utils::HTTP_STATUS_CODES.fetch(403),
        message: ErrorsController::STATUS_MESSAGES.fetch(403)
      },
      status: :forbidden
  end

  # The Team the URL names, when it names one. Falls back to the first the actor
  # can reach, so the shell always has a Team to point its links at.
  def shared_current_team_prop(teams)
    slug = params[:team_slug]
    match = slug.present? ? teams.find { |entry| entry.slug == slug } : nil

    (match || teams.first)&.then { |entry| shared_team_prop(entry) }
  end
end
