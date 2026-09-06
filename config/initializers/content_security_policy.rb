# Security headers for the Control Plane panel.
#
# This policy governs **the panel only**. It says nothing about the applications
# users deploy: Opanel does not impose a content policy on a customer's workload
# (Annex C §14).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src :self

    # Clickjacking. `frame_ancestors :none` is the header form of X-Frame-Options
    # and the one browsers actually honour for nested contexts.
    policy.frame_ancestors :none
    policy.form_action :self

    if Rails.env.development?
      # The Vite dev server is a separate origin, and HMR opens a websocket back
      # to it. React Refresh evaluates the modules it swaps in. None of this
      # applies to a built asset, so it stays scoped to development.
      vite_origin = ViteRuby.config.host_with_port

      policy.script_src(*policy.script_src, :unsafe_eval, "http://#{vite_origin}")
      policy.style_src(*policy.style_src, :unsafe_inline, "http://#{vite_origin}")
      policy.connect_src(*policy.connect_src, "http://#{vite_origin}", "ws://#{vite_origin}")
      policy.img_src(*policy.img_src, "http://#{vite_origin}")
    end
  end
end

Rails.application.config.action_dispatch.default_headers.merge!(
  # Do not leak the panel's paths — which name teams, projects and services — to
  # anything a user navigates to.
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "X-Content-Type-Options" => "nosniff",
  # The panel has no reason to reach any of these.
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
)

# HSTS is applied by `config.force_ssl` in production, which also redirects and
# marks cookies secure. It is deliberately not set here: sending HSTS from an
# environment that is not served over TLS locks a developer out of their own
# machine.
