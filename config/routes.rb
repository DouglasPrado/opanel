Rails.application.routes.draw do
  # Health and readiness of the Control Plane itself. Rails' default only proves
  # the process booted; this one reports PostgreSQL and the queue separately,
  # because they fail separately.
  get "up" => "health#show", as: :rails_health_check

  root "home#show"

  # Visual inspection of the imported component library (M00-05). Development
  # only: it is a tool for building the product, not part of it.
  get "gallery" => "gallery#show", as: :gallery if Rails.env.development? || Rails.env.test?
end
