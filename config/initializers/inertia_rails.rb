InertiaRails.configure do |config|
  # Asset versioning. When the compiled bundle changes, Inertia answers a stale
  # XHR visit with a full page reload instead of running new props against old
  # JavaScript.
  config.version = -> { ViteRuby.digest }

  # The initial page travels in a `<script type="application/json">` element.
  #
  # This is the contract the Inertia 3 client reads; the `data-page` attribute on
  # the root div is the v2 form, and the client silently finds nothing there —
  # the page renders as a blank document with one console error. It is the kind
  # of mismatch only a browser can catch, and M00-08's smoke journey is what
  # caught it.
  config.use_script_element_for_initial_page = true

  # Every response carries an `errors` hash, which is the Inertia protocol's
  # contract for form validation. Opting in now is the 4.0 default.
  config.always_include_errors_hash = true
end
