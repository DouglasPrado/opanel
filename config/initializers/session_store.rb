# Rails' own session cookie, pinned to the same attributes as the authentication
# cookie (Annex C §7.1, M01-01 AC9).
#
# This cookie is not incidental: it carries the CSRF token, the flash and the
# post-sign-in destination. A browser credential is a browser credential, and
# leaving it on framework defaults would mean AC9 held for one of the two cookies
# the application sets.
#
# `secure` is on everywhere except development, which is served over plain HTTP.
# It is deliberately on in **test** too, so the request spec that asserts the
# attribute reads the real one rather than a production-only branch that nobody
# exercises.
#
# `SameSite=Lax`, not Strict: the top-level GET that follows sign-in and any
# inbound link must still carry the session, and the state-changing requests are
# same-site and have been CSRF-protected since M00-04.
Rails.application.config.session_store :cookie_store,
  key: "_opanel_session",
  httponly: true,
  same_site: :lax,
  secure: !Rails.env.development?
