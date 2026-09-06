# Reads the initial page an Inertia response carries.
#
# The payload lives in a `<script data-page="app" type="application/json">`
# element (the Inertia 3 contract). Parsing it in one place means a change to that
# contract breaks one helper instead of every request spec — which is exactly the
# failure M00-08 found when the client and the Rails adapter disagreed.
module InertiaResponse
  # A test client with no user agent is refused by `allow_browser`.
  MODERN_BROWSER_HEADERS = {
    "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                         "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
  }.freeze

  def modern_browser
    MODERN_BROWSER_HEADERS
  end

  def inertia_payload(body = response.body)
    raw = body[%r{<script[^>]*data-page="app"[^>]*>(.*?)</script>}m, 1]
    raise "response is not an Inertia page: #{body[0, 200]}" if raw.nil?

    JSON.parse(CGI.unescapeHTML(raw))
  end

  def inertia_props(body = response.body)
    inertia_payload(body).fetch("props")
  end
end

RSpec.configure do |config|
  config.include InertiaResponse, type: :request
  config.include InertiaResponse, type: :security
end
