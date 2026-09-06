# Renders an unhandled failure as a page the operator can act on.
#
# Two things must be true of every error response, and Rails' static pages give
# neither: the `request_id` has to be visible so a user can quote it to support and
# it can be found in the server log (doc 09 §28), and nothing internal may leak —
# no stack trace, no SQL, no filesystem path, no cryptographic material
# (Annex C §17).
#
# Wired through `config.exceptions_app`, so it covers exceptions raised anywhere in
# the stack, not only inside a controller.
class ErrorsController < ApplicationController
  # A browser too old for the application still has to be able to read why it was
  # refused, and CSRF cannot be verified on a request that already failed.
  skip_forgery_protection
  allow_browser versions: :modern, block: -> { render_error(406) }

  STATUS_MESSAGES = {
    400 => "That request could not be understood.",
    403 => "You do not have access to this.",
    404 => "That page does not exist.",
    406 => "This browser is not supported.",
    422 => "That change could not be applied.",
    500 => "Something went wrong on our side."
  }.freeze

  def show
    render_error(derived_status)
  end

  private

  def render_error(status)
    render inertia: "Error",
      props: {
        status: status,
        title: Rack::Utils::HTTP_STATUS_CODES.fetch(status, "Error"),
        # Deliberately a fixed sentence per status. The exception's own message can
        # carry a query, a path or a credential, and this response is shown to a
        # user.
        message: STATUS_MESSAGES.fetch(status, STATUS_MESSAGES[500])
      },
      status: status
  end

  def derived_status
    exception = request.env["action_dispatch.exception"]
    wrapper = ActionDispatch::ExceptionWrapper.new(
      request.env["action_dispatch.backtrace_cleaner"], exception
    )

    STATUS_MESSAGES.key?(wrapper.status_code) ? wrapper.status_code : 500
  end
end
