# Sign up (doc 10 UC-001).
#
# Public by declaration, not by omission: `allow_unauthenticated_access` is what
# `Authentication`'s deny-by-default requires a public controller to say.
class RegistrationsController < ApplicationController
  include ErrorEnvelope

  allow_unauthenticated_access

  PAGE = "Auth/SignUp"

  def new
    return redirect_to root_path if signed_in?

    render inertia: PAGE
  end

  def create
    result = RegisterUser.call(
      email: submitted[:email],
      password: submitted[:password],
      display_name: submitted[:display_name],
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    if result.failure?
      return render inertia: PAGE,
        props: { error: error_envelope(result) },
        status: error_status(result)
    end

    start_session(result.value.fetch(:session), result.value.fetch(:session_token))
    # The panel of the Team the bootstrap just created, not the example page.
    redirect_to destination_after_authentication
  end

  private

  # `permit` rather than `require`: a missing field is a validation failure the
  # Command states in the user's language, not a 400 with Rails' wording.
  def submitted
    params.permit(:email, :password, :display_name)
  end
end
