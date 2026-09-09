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

  # The Team the URL names, when it names one. Falls back to the first the actor
  # can reach, so the shell always has a Team to point its links at.
  def shared_current_team_prop(teams)
    slug = params[:team_slug]
    match = slug.present? ? teams.find { |entry| entry.slug == slug } : nil

    (match || teams.first)&.then { |entry| shared_team_prop(entry) }
  end
end
