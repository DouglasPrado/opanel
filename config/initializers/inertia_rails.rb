InertiaRails.configure do |config|
  # Asset versioning. When the compiled bundle changes, Inertia answers a stale
  # XHR visit with a full page reload instead of running new props against old
  # JavaScript.
  config.version = -> { ViteRuby.digest }

  # Every response carries an `errors` hash, which is the Inertia protocol's
  # contract for form validation. Opting in now is the 4.0 default.
  config.always_include_errors_hash = true
end
