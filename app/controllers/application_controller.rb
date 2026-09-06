class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # An Inertia visit is still a form submission as far as the browser is
  # concerned, so CSRF protection applies to it exactly as it would to any other
  # non-GET request. Raising, rather than resetting the session, makes a rejected
  # request visible instead of silently anonymous.
  protect_from_forgery with: :exception

  before_action :assign_request_id

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
    }
  end

  private

  # `request_id` reaches the browser, the log line and — from M00-15 — the job
  # enqueued by this request, so a user-visible failure can be traced without
  # asking the user to reproduce it.
  def assign_request_id
    Current.correlation_id = request.request_id
  end
end
