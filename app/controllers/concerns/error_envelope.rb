# The stable error model of doc 09 §28 — `code`, `message`, `requestId` — used
# from the first Story that can fail, so nothing after it has to invent a second
# shape and translate between them.
#
# The failure is rendered rather than redirected. A redirect cannot carry a
# status, and the status is part of the contract: 429 for a throttled request is
# what a client, a CLI and a proxy all understand without reading the body. The
# page comes back with the same props it was rendered with plus an `error` prop,
# so the browser stays on the form it submitted.
#
# `errors` — Inertia's own validation bag, already a shared prop — is deliberately
# left alone. Overloading it here would put this envelope in the shared surface
# that `spec/security/inertia_shared_props_spec.rb` guards.
module ErrorEnvelope
  extend ActiveSupport::Concern

  # Only codes this Story can produce. doc 09 §28 calls its list "Exemplos de
  # code", so specializing it is allowed; inventing a status for an unlisted code
  # is not, which is why the default is 422 rather than something optimistic.
  STATUSES = {
    "VALIDATION_ERROR" => :unprocessable_content,
    "INVALID_CREDENTIALS" => :unprocessable_content,
    "EMAIL_UNAVAILABLE" => :unprocessable_content,
    "RATE_LIMITED" => :too_many_requests,
    "NOT_FOUND" => :not_found,
    "FORBIDDEN" => :forbidden,
    # A request that is well formed and permitted, refused because the resource
    # is in a state that does not accept it — archiving a Project that is already
    # archived. 409 rather than 422: nothing about the request needs correcting,
    # so a client that retries after the state changes is right to.
    "CONFLICT" => :conflict,
    # Optimistic concurrency: the resource was modified since the caller last read it (doc 09 §5.3, M01-13).
    "REVISION_CONFLICT" => :conflict
  }.freeze

  private

  # The whole envelope, and nothing else. No exception class, no backtrace, no
  # SQL, no path (Annex C §17).
  def error_envelope(result)
    {
      code: result.code,
      message: result.message,
      requestId: request.request_id
    }
  end

  def error_status(result)
    STATUSES.fetch(result.code, :unprocessable_content)
  end
end
